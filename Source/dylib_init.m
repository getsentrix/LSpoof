#import "LocationSpoofer.h"
#import "PersistenceManager.h"
#import "OverlayWindow.h"
#import "LSUpdateChecker.h"

__attribute__((constructor(101)))
static void LSDylibInit(void) {
    [PersistenceManager loadEarly];
    [LocationSpoofer installHooks];

    dispatch_async(dispatch_get_main_queue(), ^{
        [LSOverlayManager install];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [LSUpdateChecker checkForUpdatesAutomatically];
        });
    });
}
