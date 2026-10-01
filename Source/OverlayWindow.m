#import "OverlayWindow.h"
#import "LocationSpoofer.h"
#import "MapPickerViewController.h"
#import "PersistenceManager.h"
#import "LSHooking.h"
#import "LSUpdateChecker.h"

#import <objc/runtime.h>
#import <os/log.h>

static const NSTimeInterval kLSThreeFingerHoldDuration = 0.8;
static const NSTimeInterval kLSPresentationWatchdogInterval = 2.0;
static const NSInteger kLSTopBarButtonTag = 99281;

static NSHashTable *ls_sendEventSwizzledClasses = nil;
static dispatch_once_t ls_sendEventTablesOnceToken;
static NSTimer *ls_threeFingerHoldTimer = nil;
static BOOL ls_threeFingerTriggered = NO;
static BOOL ls_isPresentingMapPicker = NO;
static BOOL ls_mapPickerVisible = NO;
static os_log_t ls_overlayLog = NULL;

#if DEBUG
#define LSAssertMainThread() NSCAssert([NSThread isMainThread], @"LocationSpoofer overlay UI state must change on main thread")
#else
#define LSAssertMainThread()
#endif

@interface LSTopBarMenuButton : UIButton
@end

@implementation LSTopBarMenuButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    CGRect bounds = self.bounds;
    CGFloat widthDelta = MAX(44.0 - bounds.size.width, 0.0);
    CGFloat heightDelta = MAX(44.0 - bounds.size.height, 0.0);
    CGRect hitFrame = CGRectInset(bounds, -0.5 * widthDelta, -0.5 * heightDelta);
    return CGRectContainsPoint(hitFrame, point);
}

@end

@interface LSOverlayManager ()
+ (instancetype)shared;
@property (nonatomic, assign) BOOL installed;
@property (nonatomic, strong, nullable) LSTopBarMenuButton *topBarButton;
@property (nonatomic, strong, nullable) NSTimer *topBarAttachTimer;
- (void)setupTopBarButtonIfNeeded;
- (void)updateButtonVisibility;
@end

static void LSUpdateThreeFingerHoldForEvent(UIEvent *event);

@interface LSSendEventHookTemplate : NSObject
- (void)lsp_applicationSendEvent:(UIEvent *)event;
- (void)lsp_windowSendEvent:(UIEvent *)event;
@end

static void LSInitializeSendEventTables(void) {
    dispatch_once(&ls_sendEventTablesOnceToken, ^{
        ls_sendEventSwizzledClasses = [NSHashTable weakObjectsHashTable];
        ls_overlayLog = os_log_create("com.locationspoofer.dylib", "overlay");
    });
}

static NSInteger LSActiveTouchCountForEvent(UIEvent * _Nullable event) {
    if (!event) {
        return 0;
    }

    NSSet *touches = event.allTouches;
    if (touches.count < 3) {
        return 0;
    }

    NSInteger activeTouches = 0;
    for (UITouch *touch in touches) {
        switch (touch.phase) {
            case UITouchPhaseBegan:
            case UITouchPhaseMoved:
            case UITouchPhaseStationary:
                activeTouches += 1;
                break;
            default:
                break;
        }
    }
    return activeTouches;
}

static Class LSSendEventHookTargetClass(void) {
    Class targetClass = [UIApplication class];
    UIApplication *application = UIApplication.sharedApplication;
    if (application && LSClassDefinesInstanceMethodLocally([application class], @selector(sendEvent:))) {
        targetClass = [application class];
    }
    return targetClass;
}

static void LSSwizzleSendEventOnClass(Class cls, SEL hookSelector) {
    if (!cls) {
        return;
    }

    if (!LSClassDefinesInstanceMethodLocally(cls, @selector(sendEvent:))) {
        return;
    }

    LSInitializeSendEventTables();
    @synchronized(ls_sendEventSwizzledClasses) {
        if ([ls_sendEventSwizzledClasses containsObject:cls]) {
            return;
        }

        if (LSInstallInstanceHook(cls,
                                  @selector(sendEvent:),
                                  hookSelector,
                                  [LSSendEventHookTemplate class])) {
            [ls_sendEventSwizzledClasses addObject:cls];
        }
    }
}

static void LSCancelThreeFingerHoldTimer(void) {
    [ls_threeFingerHoldTimer invalidate];
    ls_threeFingerHoldTimer = nil;
}

static void LSHandleThreeFingerHoldTimerFired(void) {
    LSCancelThreeFingerHoldTimer();
    if (ls_mapPickerVisible || ls_isPresentingMapPicker || ls_threeFingerTriggered) {
        return;
    }

    LSAssertMainThread();
    ls_threeFingerTriggered = YES;
    [LSOverlayManager presentMapPicker];
}

@implementation LSSendEventHookTemplate

- (void)lsp_applicationSendEvent:(UIEvent *)event {
    [self lsp_applicationSendEvent:event];
    LSUpdateThreeFingerHoldForEvent(event);
}

- (void)lsp_windowSendEvent:(UIEvent *)event {
    [self lsp_windowSendEvent:event];
    LSUpdateThreeFingerHoldForEvent(event);
}

@end

static void LSUpdateThreeFingerHoldForEvent(UIEvent *event) {
    if (event.type != UIEventTypeTouches || ls_mapPickerVisible || ls_isPresentingMapPicker) {
        LSCancelThreeFingerHoldTimer();
        return;
    }

    NSInteger activeTouches = LSActiveTouchCountForEvent(event);
    if (activeTouches >= 3) {
        if (ls_threeFingerHoldTimer || ls_threeFingerTriggered) {
            return;
        }

        ls_threeFingerHoldTimer = [NSTimer timerWithTimeInterval:kLSThreeFingerHoldDuration
                                                         repeats:NO
                                                           block:^(__unused NSTimer *timer) {
            LSHandleThreeFingerHoldTimerFired();
        }];

        [[NSRunLoop mainRunLoop] addTimer:ls_threeFingerHoldTimer forMode:NSRunLoopCommonModes];
    } else {
        ls_threeFingerTriggered = NO;
        LSCancelThreeFingerHoldTimer();
    }
}

static UIWindow * _Nullable LSHostKeyWindow(void) {
    UIApplication *application = UIApplication.sharedApplication;
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (!window.hidden && window.alpha > 0.01) {
                return window;
            }
        }
    }
    return application.windows.firstObject;
}

static UIViewController * _Nullable LSHostTopViewController(void) {
    UIWindow *keyWindow = LSHostKeyWindow();
    if (!keyWindow) {
        return nil;
    }

    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    return controller;
}

static UIView * _Nullable LSFindCircleNameViewInWindow(UIWindow *window) {
    if (!window) return nil;
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];

    while (queue.count > 0) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if (v.tag == kLSTopBarButtonTag) {
            continue;
        }

        CGRect f = [v convertRect:v.bounds toView:window];
        // Header bar vertical window range: y between 25 and 130, height between 32 and 60
        if (f.origin.y >= 25.0 && f.origin.y <= 130.0 && f.size.height >= 32.0 && f.size.height <= 60.0) {
            // Circle name pill sits between x=55 and x=280 and has width >= 60
            if (f.origin.x >= 55.0 && f.origin.x <= 280.0 && f.size.width >= 60.0 && f.size.width <= 260.0) {
                BOOL hasLabel = NO;
                for (UIView *sub in v.subviews) {
                    if ([sub isKindOfClass:[UILabel class]]) {
                        UILabel *l = (UILabel *)sub;
                        if (l.text.length > 0) {
                            hasLabel = YES;
                            break;
                        }
                    }
                }
                if (hasLabel || [v isKindOfClass:[UIButton class]]) {
                    [candidates addObject:v];
                }
            }
        }

        for (UIView *sub in v.subviews) {
            if (!sub.hidden && sub.alpha > 0.05) {
                [queue addObject:sub];
            }
        }
    }

    UIView *best = nil;
    CGFloat maxWidth = 0;
    for (UIView *c in candidates) {
        CGRect f = [c convertRect:c.bounds toView:window];
        if (f.size.width > maxWidth && f.size.width <= 250.0) {
            maxWidth = f.size.width;
            best = c;
        }
    }
    return best;
}

static CGRect LSFindSettingsButtonFrameInWindow(UIWindow *window) {
    if (!window) return CGRectZero;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
    while (queue.count > 0) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (v.tag == kLSTopBarButtonTag) continue;

        CGRect f = [v convertRect:v.bounds toView:window];
        if (f.origin.y >= 25.0 && f.origin.y <= 130.0 && f.origin.x >= 8.0 && f.origin.x <= 65.0 &&
            f.size.width >= 36.0 && f.size.width <= 64.0 && f.size.height >= 36.0 && f.size.height <= 64.0) {
            return f;
        }
        for (UIView *sub in v.subviews) {
            if (!sub.hidden && sub.alpha > 0.05) [queue addObject:sub];
        }
    }
    return CGRectZero;
}

@implementation LSOverlayManager

+ (instancetype)shared {
    static LSOverlayManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LSOverlayManager alloc] init];
    });
    return instance;
}

+ (void)install {
    [[self shared] installIfNeeded];
}

+ (void)presentMapPicker {
    [[self shared] presentMapPickerIfNeeded];
}

+ (void)resetGestureTriggerState {
    LSAssertMainThread();
    ls_threeFingerTriggered = NO;
    LSCancelThreeFingerHoldTimer();
}

+ (void)setFloatingButtonHidden:(BOOL)hidden {
    dispatch_async(dispatch_get_main_queue(), ^{
        LSOverlayManager *mgr = [self shared];
        [PersistenceManager shared].floatingButtonEnabled = !hidden;
        [mgr updateButtonVisibility];
    });
}

+ (void)setMapPickerVisible:(BOOL)visible {
    LSAssertMainThread();
    ls_mapPickerVisible = visible;
    LSCancelThreeFingerHoldTimer();
    LSOverlayManager *mgr = [self shared];
    dispatch_async(dispatch_get_main_queue(), ^{
        [mgr updateButtonVisibility];
    });
}

+ (void)restoreMapPickerSessionState {
    LSAssertMainThread();
    LSSetHooksBypassed(NO);
    ls_isPresentingMapPicker = NO;
    [self setMapPickerVisible:NO];
    [self resetGestureTriggerState];
}

+ (void)installSendEventHooks {
    LSSwizzleSendEventOnClass(LSSendEventHookTargetClass(), @selector(lsp_applicationSendEvent:));
}

- (void)updateButtonVisibility {
    if (!self.topBarButton) {
        return;
    }

    if (![PersistenceManager shared].floatingButtonEnabled || ls_mapPickerVisible) {
        self.topBarButton.hidden = YES;
        return;
    }

    UIViewController *topVC = LSHostTopViewController();
    if (topVC && topVC.presentedViewController && ![topVC.presentedViewController isKindOfClass:[MapPickerViewController class]]) {
        self.topBarButton.hidden = YES;
        return;
    }

    self.topBarButton.hidden = NO;
}

- (void)setupTopBarButtonIfNeeded {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setupTopBarButtonIfNeeded];
        });
        return;
    }

    UIWindow *window = LSHostKeyWindow();
    if (!window) {
        return;
    }

    CGFloat buttonWidth = 44.0;
    CGFloat buttonHeight = 44.0;
    CGFloat buttonX = 240.0;
    CGFloat buttonY = 56.0;

    UIView *circleNameView = LSFindCircleNameViewInWindow(window);
    CGRect settingsFrame = LSFindSettingsButtonFrameInWindow(window);

    if (circleNameView) {
        CGRect circleFrame = [circleNameView convertRect:circleNameView.bounds toView:window];
        buttonX = CGRectGetMaxX(circleFrame) + 8.0;
        buttonY = circleFrame.origin.y + (circleFrame.size.height - buttonHeight) / 2.0;
    } else if (settingsFrame.size.width > 0) {
        buttonY = settingsFrame.origin.y + (settingsFrame.size.height - buttonHeight) / 2.0;
        buttonX = CGRectGetMaxX(settingsFrame) + 180.0;
    } else {
        CGFloat safeTop = window.safeAreaInsets.top;
        if (safeTop <= 0) safeTop = 47.0;
        buttonY = safeTop + 4.0;
        buttonX = 240.0;
    }

    // Clamp buttonX so it never clips past screen bounds or overlaps right action buttons
    CGFloat screenW = window.bounds.size.width;
    if (screenW > 0 && (buttonX + buttonWidth) > (screenW - 56.0)) {
        buttonX = screenW - buttonWidth - 56.0;
    }
    if (buttonX < 70.0) {
        buttonX = 70.0;
    }

    CGRect targetFrame = CGRectMake(buttonX, buttonY, buttonWidth, buttonHeight);

    if (!self.topBarButton) {
        LSTopBarMenuButton *button = [LSTopBarMenuButton buttonWithType:UIButtonTypeCustom];
        button.tag = kLSTopBarButtonTag;
        button.frame = targetFrame;
        button.backgroundColor = UIColor.whiteColor;
        button.layer.cornerRadius = buttonWidth / 2.0;
        if (@available(iOS 13.0, *)) {
            button.layer.cornerCurve = kCACornerCurveContinuous;
        }
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        button.layer.shadowOpacity = 0.15;
        button.layer.shadowRadius = 4.0;
        button.layer.masksToBounds = NO;
        button.layer.borderWidth = 0.5;
        button.layer.borderColor = [UIColor colorWithWhite:0.0 alpha:0.06].CGColor;

        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIFontWeightBold];
        UIImage *icon = [UIImage systemImageNamed:@"location.fill" withConfiguration:config];
        if (!icon) icon = [UIImage systemImageNamed:@"mappin.circle.fill" withConfiguration:config];
        if (!icon) icon = [UIImage systemImageNamed:@"circle.fill" withConfiguration:config];
        [button setImage:icon forState:UIControlStateNormal];
        // Exact Life360 purple
        button.tintColor = [UIColor colorWithRed:0.43 green:0.25 blue:0.85 alpha:1.0];

        [button addTarget:self action:@selector(handleMenuButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        self.topBarButton = button;
    } else {
        if (fabs(self.topBarButton.frame.origin.x - targetFrame.origin.x) > 1.0 ||
            fabs(self.topBarButton.frame.origin.y - targetFrame.origin.y) > 1.0) {
            self.topBarButton.frame = targetFrame;
        }
    }

    if (self.topBarButton.superview != window) {
        [self.topBarButton removeFromSuperview];
        [window addSubview:self.topBarButton];
    }
    [window bringSubviewToFront:self.topBarButton];

    [self updateButtonVisibility];
}

- (void)handleMenuButtonTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *impact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [impact impactOccurred];

    [UIView animateWithDuration:0.08 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.90, 0.90);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.12 animations:^{
            sender.transform = CGAffineTransformIdentity;
        }];
    }];

    [LSOverlayManager presentMapPicker];
}

- (void)startTopBarButtonMonitor {
    if (self.topBarAttachTimer) {
        return;
    }
    self.topBarAttachTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                             repeats:YES
                                                               block:^(__unused NSTimer *timer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[LSOverlayManager shared] setupTopBarButtonIfNeeded];
        });
    }];
}

- (void)installIfNeeded {
    if (self.installed) {
        return;
    }

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self installIfNeeded];
        });
        return;
    }

    [LSOverlayManager installSendEventHooks];

    for (NSNumber *delay in @[@0.2, @0.5, @1.0, @2.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self setupTopBarButtonIfNeeded];
        });
    }
    [self startTopBarButtonMonitor];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationDidFinishLaunching:)
                                                 name:UIApplicationDidFinishLaunchingNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleApplicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];

    self.installed = YES;
}

- (void)handleApplicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [LSOverlayManager installSendEventHooks];
    [self setupTopBarButtonIfNeeded];
}

- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    [LSOverlayManager installSendEventHooks];
    [self setupTopBarButtonIfNeeded];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [LSUpdateChecker checkForUpdatesAutomatically];
    });
}

- (void)handleApplicationDidEnterBackground:(NSNotification *)notification {
    (void)notification;
    [LSOverlayManager restoreMapPickerSessionState];
}

- (void)presentMapPickerIfNeeded {
    if (ls_isPresentingMapPicker || ls_mapPickerVisible) {
        return;
    }

    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentMapPickerIfNeeded];
        });
        return;
    }

    UIViewController *hostController = LSHostTopViewController();
    if (!hostController || hostController.presentedViewController) {
        ls_threeFingerTriggered = NO;
        return;
    }

    LSAssertMainThread();
    ls_isPresentingMapPicker = YES;
    self.topBarButton.hidden = YES;

    MapPickerViewController *mapPicker = [[MapPickerViewController alloc] init];
    mapPicker.modalPresentationStyle = UIModalPresentationPageSheet;

    if (@available(iOS 13.0, *)) {
        BOOL isDark = [[PersistenceManager shared] isEffectiveDarkMode];
        mapPicker.overrideUserInterfaceStyle = isDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    }

    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = mapPicker.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[[UISheetPresentationControllerDetent largeDetent]];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 24.0;
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLSPresentationWatchdogInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        LSAssertMainThread();
        if (ls_isPresentingMapPicker) {
            ls_isPresentingMapPicker = NO;
        }
    });

    [hostController presentViewController:mapPicker animated:YES completion:^{
        LSAssertMainThread();
        ls_isPresentingMapPicker = NO;
    }];
}

@end
