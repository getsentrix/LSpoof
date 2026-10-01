#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LSAppearancePreference) {
    LSAppearancePreferenceSystem = 0,
    LSAppearancePreferenceDark = 1,
    LSAppearancePreferenceLight = 2
};

@interface PersistenceManager : NSObject

+ (instancetype)shared;

+ (void)loadEarly;

- (BOOL)isSpoofingEnabled;
- (CLLocationCoordinate2D)spoofCoordinate;
- (BOOL)hasStoredCoordinate;

@property (nonatomic, assign) BOOL simulationWasActive;
@property (nonatomic, assign) double altitude;
@property (nonatomic, assign) CLLocationDirection heading;
@property (nonatomic, assign) BOOL fluctuationEnabled;
@property (nonatomic, assign) double fluctuationRadius;
@property (nonatomic, assign) BOOL keepLastSpoof;
@property (nonatomic, assign) BOOL showRealLocation;
@property (nonatomic, assign) CLLocationCoordinate2D lastRealCoordinate;
@property (nonatomic, assign) BOOL hasRealCoordinate;
@property (nonatomic, assign) LSAppearancePreference appearancePreference;
@property (nonatomic, readonly) BOOL isEffectiveDarkMode;
@property (nonatomic, assign) BOOL floatingButtonEnabled;
@property (nonatomic, assign) CGPoint floatingButtonPosition;

- (NSArray<NSDictionary *> *)recentLocations;
- (void)recordRecentCoordinate:(CLLocationCoordinate2D)coordinate name:(nullable NSString *)name;
- (void)updateRecentCoordinateName:(NSString *)name forCoordinate:(CLLocationCoordinate2D)coordinate;


- (BOOL)setSpoofCoordinate:(CLLocationCoordinate2D)coordinate enabled:(BOOL)enabled;
- (void)clearSpoof;
- (void)clearLastSpoof;

@end

NS_ASSUME_NONNULL_END
