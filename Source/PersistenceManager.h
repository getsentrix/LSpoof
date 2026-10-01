#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

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
@property (nonatomic, assign) NSInteger appearancePreference; // 0 = System, 1 = Dark, 2 = Light
@property (nonatomic, readonly) BOOL isEffectiveDarkMode;

- (NSArray<NSDictionary *> *)recentLocations;
- (void)recordRecentCoordinate:(CLLocationCoordinate2D)coordinate name:(nullable NSString *)name;
- (void)updateRecentCoordinateName:(NSString *)name forCoordinate:(CLLocationCoordinate2D)coordinate;


- (BOOL)setSpoofCoordinate:(CLLocationCoordinate2D)coordinate enabled:(BOOL)enabled;
- (void)clearSpoof;
- (void)clearLastSpoof;

@end

NS_ASSUME_NONNULL_END
