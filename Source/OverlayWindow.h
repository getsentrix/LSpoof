#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSOverlayManager : NSObject

+ (void)install;
+ (void)presentMapPicker;
+ (void)resetGestureTriggerState;
+ (void)setMapPickerVisible:(BOOL)visible;
+ (void)restoreMapPickerSessionState;
+ (void)setFloatingButtonHidden:(BOOL)hidden;

@end

NS_ASSUME_NONNULL_END
