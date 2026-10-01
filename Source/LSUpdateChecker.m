#import "LSUpdateChecker.h"

NSString * const LSpoofCurrentVersion = @"1.1.9";
NSString * const LSpoofGitHubReleasesURL = @"https://github.com/getsentrix/LSpoof/releases/latest";
static NSString * const kLSpoofApiReleasesURL = @"https://api.github.com/repos/getsentrix/LSpoof/releases/latest";
static NSString * const kLSLastCheckDefaultsKey = @"LSpoofLastUpdateCheckTimestamp";
static const NSTimeInterval kLSUpdateCooldownInterval = 14400.0; // 4 hours

@interface LSUpdateChecker ()
@property (nonatomic, assign) BOOL hasCheckedThisSession;
@property (nonatomic, assign) BOOL isChecking;
@end

@implementation LSUpdateChecker

+ (instancetype)sharedChecker {
    static LSUpdateChecker *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[LSUpdateChecker alloc] init];
    });
    return instance;
}

+ (NSString *)currentVersion {
    return LSpoofCurrentVersion;
}

+ (void)checkForUpdatesAutomatically {
    [[self sharedChecker] performCheckIsManual:NO fromViewController:nil];
}

+ (void)checkForUpdatesManuallyFromViewController:(nullable UIViewController *)viewController {
    [[self sharedChecker] performCheckIsManual:YES fromViewController:viewController];
}

- (void)performCheckIsManual:(BOOL)isManual fromViewController:(nullable UIViewController *)viewController {
    if (self.isChecking) {
        return;
    }

    if (!isManual) {
        if (self.hasCheckedThisSession) {
            return;
        }

        NSTimeInterval lastCheck = [[NSUserDefaults standardUserDefaults] doubleForKey:kLSLastCheckDefaultsKey];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (lastCheck > 0 && (now - lastCheck) < kLSUpdateCooldownInterval) {
            self.hasCheckedThisSession = YES;
            return;
        }
    }

    self.isChecking = YES;
    self.hasCheckedThisSession = YES;
    [[NSUserDefaults standardUserDefaults] setDouble:[[NSDate date] timeIntervalSince1970] forKey:kLSLastCheckDefaultsKey];

    NSURL *url = [NSURL URLWithString:kLSpoofApiReleasesURL];
    if (!url) {
        self.isChecking = NO;
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:10.0];
    [request setValue:@"LSpoof-Updater" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github.v3+json" forHTTPHeaderField:@"Accept"];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                 completionHandler:^(NSData * _Nullable data,
                                                                                     NSURLResponse * _Nullable response,
                                                                                     NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf.isChecking = NO;
                [strongSelf handleCheckResponseWithData:data
                                               response:response
                                                  error:error
                                               isManual:isManual
                                     fromViewController:viewController];
            }
        });
    }];
    [task resume];
}

- (void)handleCheckResponseWithData:(nullable NSData *)data
                           response:(nullable NSURLResponse *)response
                              error:(nullable NSError *)error
                           isManual:(BOOL)isManual
                 fromViewController:(nullable UIViewController *)viewController {
    if (error || !data) {
        if (isManual) {
            [self showAlertWithTitle:@"Update Check Failed"
                             message:@"Could not connect to GitHub. Please check your internet connection."
                  fromViewController:viewController];
        }
        return;
    }

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if ([httpResponse isKindOfClass:[NSHTTPURLResponse class]] && httpResponse.statusCode != 200) {
        if (isManual) {
            [self showAlertWithTitle:@"Update Check Failed"
                             message:[NSString stringWithFormat:@"GitHub returned HTTP status %ld.", (long)httpResponse.statusCode]
                  fromViewController:viewController];
        }
        return;
    }

    NSError *jsonError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError || ![json isKindOfClass:[NSDictionary class]]) {
        if (isManual) {
            [self showAlertWithTitle:@"Update Check Failed"
                             message:@"Could not parse release information from GitHub."
                  fromViewController:viewController];
        }
        return;
    }

    NSString *tagName = json[@"tag_name"];
    if (![tagName isKindOfClass:[NSString class]] || tagName.length == 0) {
        return;
    }

    NSCharacterSet *trimSet = [NSCharacterSet characterSetWithCharactersInString:@"vV \t\r\n"];
    NSString *latestVersion = [tagName stringByTrimmingCharactersInSet:trimSet];
    NSString *currentVersion = [LSpoofCurrentVersion stringByTrimmingCharactersInSet:trimSet];

    NSComparisonResult comparison = [latestVersion compare:currentVersion options:NSNumericSearch];
    if (comparison == NSOrderedDescending) {
        // Newer version available
        [self showUpdatePromptForVersion:latestVersion fromViewController:viewController];
    } else if (isManual) {
        // Up to date
        [self showAlertWithTitle:@"LSpoof is Up to Date"
                         message:[NSString stringWithFormat:@"You are running the latest version (v%@).", currentVersion]
              fromViewController:viewController];
    }
}

- (void)showUpdatePromptForVersion:(NSString *)latestVersion fromViewController:(nullable UIViewController *)viewController {
    UIViewController *presentingVC = viewController ?: [self topViewController];
    if (!presentingVC) {
        return;
    }

    // Avoid presenting if an alert is already presented
    if ([presentingVC.presentedViewController isKindOfClass:[UIAlertController class]]) {
        return;
    }

    NSString *title = @"Update Available";
    NSString *message = [NSString stringWithFormat:@"A new version of LSpoof (v%@) is available on GitHub.\n\nPlease download the updated dylib to update.", latestVersion];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *downloadAction = [UIAlertAction actionWithTitle:@"Download from GitHub"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(__unused UIAlertAction * _Nonnull action) {
        NSURL *url = [NSURL URLWithString:LSpoofGitHubReleasesURL];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }];

    UIAlertAction *laterAction = [UIAlertAction actionWithTitle:@"Later"
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil];

    [alert addAction:downloadAction];
    [alert addAction:laterAction];

    [presentingVC presentViewController:alert animated:YES completion:nil];
}

- (void)showAlertWithTitle:(NSString *)title
                   message:(NSString *)message
        fromViewController:(nullable UIViewController *)viewController {
    UIViewController *presentingVC = viewController ?: [self topViewController];
    if (!presentingVC) {
        return;
    }

    if ([presentingVC.presentedViewController isKindOfClass:[UIAlertController class]]) {
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil];
    [alert addAction:okAction];
    [presentingVC presentViewController:alert animated:YES completion:nil];
}

- (nullable UIViewController *)topViewController {
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
        return nil;
    }

    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }

    return controller;
}

@end
