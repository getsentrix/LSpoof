#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const LSpoofCurrentVersion;
FOUNDATION_EXPORT NSString * const LSpoofGitHubReleasesURL;

@interface LSUpdateChecker : NSObject

+ (instancetype)sharedChecker;

/// Current dylib version string (e.g. @"1.1.3")
+ (NSString *)currentVersion;

/// Checks for updates automatically once per session (with 4h cooldown).
/// Presents an alert popup if a newer release tag is found on GitHub.
+ (void)checkForUpdatesAutomatically;

/// Forces an immediate manual check, presenting an alert with results.
+ (void)checkForUpdatesManuallyFromViewController:(nullable UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
