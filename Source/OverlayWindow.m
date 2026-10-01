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

@interface LSOverlayManager ()
+ (instancetype)shared;
@property (nonatomic, assign) BOOL installed;
@property (nonatomic, strong, nullable) UIButton *topBarButton;
@property (nonatomic, strong, nullable) NSTimer *topBarAttachTimer;
- (void)setupTopBarButtonIfNeeded;
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

static UIViewController *LSHostTopViewController(void) {
    UIApplication *application = UIApplication.sharedApplication;
    UIWindow *keyWindow = nil;

    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow) break;
    }

    if (!keyWindow) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden && window.alpha > 0.01) {
                    keyWindow = window;
                    break;
                }
            }
            if (keyWindow) break;
        }
    }

    if (!keyWindow) {
        keyWindow = application.windows.firstObject;
    }

    if (!keyWindow) {
        if (ls_overlayLog) {
            os_log_error(ls_overlayLog, "No key window found for map picker presentation");
        }
        return nil;
    }

    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }

    return controller;
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
        if (mgr.topBarButton) {
            mgr.topBarButton.hidden = hidden;
        }
    });
}

+ (void)setMapPickerVisible:(BOOL)visible {
    LSAssertMainThread();
    ls_mapPickerVisible = visible;
    LSCancelThreeFingerHoldTimer();
    LSOverlayManager *mgr = [self shared];
    if (mgr.topBarButton) {
        if (visible) {
            mgr.topBarButton.hidden = YES;
        } else {
            mgr.topBarButton.hidden = ![PersistenceManager shared].floatingButtonEnabled;
            [mgr setupTopBarButtonIfNeeded];
        }
    }
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

- (void)setupTopBarButtonIfNeeded {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setupTopBarButtonIfNeeded];
        });
        return;
    }

    UIViewController *topVC = LSHostTopViewController();
    if (!topVC || !topVC.view) {
        return;
    }

    // Search topVC.view hierarchy for Life360 header elements (Settings button and Circle Name pill)
    __block UIView *targetContainer = topVC.view;
    __block CGRect circleNameFrame = CGRectZero;
    __block CGRect settingsFrame = CGRectZero;
    __block UIView *circleNameView = nil;

    void (^searchBlock)(UIView *, void (^)(UIView *, id)) = ^(UIView *root, void (^recurse)(UIView *, id)) {
        for (UIView *sub in root.subviews) {
            if (sub.hidden || sub.alpha < 0.05) continue;
            CGRect f = [sub convertRect:sub.bounds toView:topVC.view];
            if (f.origin.y >= 20.0 && f.origin.y <= 130.0 && f.size.height >= 30.0 && f.size.height <= 64.0) {
                if (f.origin.x < 70.0 && f.size.width >= 36.0 && f.size.width <= 64.0) {
                    settingsFrame = f;
                } else if (f.origin.x >= 60.0 && f.origin.x <= 280.0 && f.size.width >= 70.0) {
                    if (f.size.width > circleNameFrame.size.width) {
                        circleNameFrame = f;
                        circleNameView = sub;
                    }
                }
            }
            recurse(sub, recurse);
        }
    };
    searchBlock(topVC.view, searchBlock);

    CGFloat buttonWidth = 44.0;
    CGFloat buttonHeight = 44.0;
    CGFloat buttonY = 56.0;
    CGFloat buttonX = 245.0;

    if (circleNameView && circleNameFrame.size.width > 0) {
        targetContainer = circleNameView.superview ?: topVC.view;
        CGRect inContainer = [circleNameView.superview convertRect:circleNameFrame fromView:topVC.view];
        // Position right next to circle name with circle name to the left
        buttonX = CGRectGetMaxX(inContainer) + 8.0;
        buttonY = inContainer.origin.y + (inContainer.size.height - buttonHeight) / 2.0;
    } else if (settingsFrame.size.width > 0) {
        buttonY = settingsFrame.origin.y + (settingsFrame.size.height - buttonHeight) / 2.0;
        buttonX = CGRectGetMaxX(settingsFrame) + 180.0;
    } else {
        CGFloat safeTop = topVC.view.safeAreaInsets.top;
        if (safeTop <= 0) safeTop = 47.0;
        buttonY = safeTop + 6.0;
        buttonX = 245.0;
    }

    // Clamp buttonX to protect right-side action buttons (mail / chat)
    CGFloat screenW = topVC.view.bounds.size.width;
    if (screenW > 0 && (buttonX + buttonWidth) > (screenW - 56.0)) {
        buttonX = screenW - buttonWidth - 56.0;
    }

    if (!self.topBarButton) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(buttonX, buttonY, buttonWidth, buttonHeight);
        button.backgroundColor = UIColor.whiteColor;
        button.layer.cornerRadius = buttonWidth / 2.0;
        if (@available(iOS 13.0, *)) {
            button.layer.cornerCurve = kCACornerCurveContinuous;
        }
        button.layer.shadowColor = UIColor.blackColor.CGColor;
        button.layer.shadowOffset = CGSizeMake(0.0, 2.0);
        button.layer.shadowOpacity = 0.14;
        button.layer.shadowRadius = 4.0;
        button.layer.masksToBounds = NO;

        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIFontWeightBold];
        UIImage *icon = [UIImage systemImageNamed:@"location.fill" withConfiguration:config];
        if (!icon) icon = [UIImage systemImageNamed:@"mappin.circle.fill" withConfiguration:config];
        if (!icon) icon = [UIImage systemImageNamed:@"circle.fill" withConfiguration:config];
        [button setImage:icon forState:UIControlStateNormal];
        // Life360 purple
        button.tintColor = [UIColor colorWithRed:0.43 green:0.25 blue:0.85 alpha:1.0];

        [button addTarget:self action:@selector(handleMenuButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        self.topBarButton = button;
    } else {
        self.topBarButton.frame = CGRectMake(buttonX, buttonY, buttonWidth, buttonHeight);
    }

    if (self.topBarButton.superview != targetContainer) {
        [self.topBarButton removeFromSuperview];
        [targetContainer addSubview:self.topBarButton];
    }
    [targetContainer bringSubviewToFront:self.topBarButton];

    BOOL enabled = [PersistenceManager shared].floatingButtonEnabled;
    self.topBarButton.hidden = !enabled || ls_mapPickerVisible;
}

- (void)handleMenuButtonTapped:(UIButton *)sender {
    UIImpactFeedbackGenerator *impact = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [impact impactOccurred];

    [UIView animateWithDuration:0.1 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.90, 0.90);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            sender.transform = CGAffineTransformIdentity;
        }];
    }];

    [LSOverlayManager presentMapPicker];
}

- (void)startTopBarButtonMonitor {
    if (self.topBarAttachTimer) {
        return;
    }
    self.topBarAttachTimer = [NSTimer scheduledTimerWithTimeInterval:2.5
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self setupTopBarButtonIfNeeded];
        [self startTopBarButtonMonitor];
    });

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
