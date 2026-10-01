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

@class LSFloatingOverlayWindow;

@interface LSOverlayManager ()
+ (instancetype)shared;
@property (nonatomic, assign) BOOL installed;
@property (nonatomic, strong, nullable) LSFloatingOverlayWindow *floatingWindow;
@property (nonatomic, strong, nullable) UIButton *floatingButton;
- (void)setupFloatingButtonIfNeeded;
@end

@interface LSFloatingOverlayWindow : UIWindow
@property (nonatomic, weak, nullable) UIButton *floatingButton;
@end

@implementation LSFloatingOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self.floatingButton || [hitView isDescendantOfView:self.floatingButton]) {
        return hitView;
    }
    return nil;
}

@end

@interface LSFloatingRootViewController : UIViewController
@end

@implementation LSFloatingRootViewController

- (BOOL)prefersStatusBarHidden {
    return NO;
}

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

        if (!keyWindow) {
            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden && window.alpha > 0.01) {
                    keyWindow = window;
                    break;
                }
            }
        }

        if (keyWindow) {
            break;
        }
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
        if (mgr.floatingButton) {
            mgr.floatingButton.hidden = hidden;
        }
    });
}

+ (void)setMapPickerVisible:(BOOL)visible {
    LSAssertMainThread();
    ls_mapPickerVisible = visible;
    LSCancelThreeFingerHoldTimer();
    LSOverlayManager *mgr = [self shared];
    if (mgr.floatingButton && [PersistenceManager shared].floatingButtonEnabled) {
        [UIView animateWithDuration:0.2 animations:^{
            mgr.floatingButton.alpha = visible ? 0.0 : 1.0;
        }];
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

- (void)setupFloatingButtonIfNeeded {
    if (self.floatingWindow && self.floatingButton) {
        return;
    }

    UIApplication *app = UIApplication.sharedApplication;
    UIWindowScene *activeScene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                if (ws.activationState == UISceneActivationStateForegroundActive) {
                    activeScene = ws;
                    break;
                }
                if (!activeScene) {
                    activeScene = ws;
                }
            }
        }
    }

    LSFloatingOverlayWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        if (activeScene) {
            window = [[LSFloatingOverlayWindow alloc] initWithWindowScene:activeScene];
        }
    }
    if (!window) {
        window = [[LSFloatingOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    }

    window.windowLevel = UIWindowLevelAlert + 100.0;
    window.backgroundColor = UIColor.clearColor;
    window.rootViewController = [[LSFloatingRootViewController alloc] init];
    window.hidden = NO;

    // Create circular white floating button with purple location icon matching Life360 UI buttons
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
    button.backgroundColor = UIColor.whiteColor;
    button.layer.cornerRadius = 22.0;
    if (@available(iOS 13.0, *)) {
        button.layer.cornerCurve = kCACornerCurveContinuous;
    }
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOffset = CGSizeMake(0.0, 2.0);
    button.layer.shadowOpacity = 0.16;
    button.layer.shadowRadius = 4.0;
    button.layer.masksToBounds = NO;

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:19.0 weight:UIFontWeightBold];
    UIImage *icon = [UIImage systemImageNamed:@"location.fill" withConfiguration:config];
    if (!icon) {
        icon = [UIImage systemImageNamed:@"mappin.circle.fill" withConfiguration:config];
    }
    if (!icon) {
        icon = [UIImage systemImageNamed:@"circle.fill" withConfiguration:config];
    }
    [button setImage:icon forState:UIControlStateNormal];
    // Vibrant purple matching Life360 settings button
    button.tintColor = [UIColor colorWithRed:0.43 green:0.25 blue:0.85 alpha:1.0];

    [button addTarget:self action:@selector(handleFloatingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFloatingButtonPan:)];
    [button addGestureRecognizer:pan];

    CGPoint pos = [PersistenceManager shared].floatingButtonPosition;
    if (pos.x <= 0 || pos.y <= 0) {
        // Position right next to settings button (Settings is at x≈20, y≈56)
        pos = CGPointMake(74.0, 56.0);
    }
    button.center = pos;

    [window.rootViewController.view addSubview:button];
    window.floatingButton = button;
    self.floatingButton = button;
    self.floatingWindow = window;

    BOOL enabled = [PersistenceManager shared].floatingButtonEnabled;
    self.floatingButton.hidden = !enabled;
}

- (void)handleFloatingButtonTapped:(UIButton *)sender {
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

- (void)handleFloatingButtonPan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.floatingWindow];
    CGPoint center = self.floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;
    self.floatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:self.floatingWindow];

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        CGRect bounds = self.floatingWindow.bounds;
        CGFloat minX = 26.0;
        CGFloat maxX = bounds.size.width - 26.0;
        CGFloat minY = 50.0;
        CGFloat maxY = bounds.size.height - 50.0;
        CGPoint clamped = self.floatingButton.center;
        clamped.x = MAX(minX, MIN(maxX, clamped.x));
        clamped.y = MAX(minY, MIN(maxY, clamped.y));
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.floatingButton.center = clamped;
        } completion:nil];
        [PersistenceManager shared].floatingButtonPosition = clamped;
    }
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
        [self setupFloatingButtonIfNeeded];
    });

    // Singleton retains observers for process lifetime.
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
    [self setupFloatingButtonIfNeeded];
}

- (void)handleApplicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    [LSOverlayManager installSendEventHooks];
    [self setupFloatingButtonIfNeeded];
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
