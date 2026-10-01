#import "MapPickerViewController.h"
#import "RouteSimulator.h"

#import <MapKit/MapKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LSMapPickerPanelTab) {
    LSMapPickerPanelTabLocation = 0,
    LSMapPickerPanelTabRoute = 1,
    LSMapPickerPanelTabSaved = 2,
    LSMapPickerPanelTabMap = 0,
    LSMapPickerPanelTabBookmarks = 2
};

typedef NS_ENUM(NSInteger, LSMapPickerCoordinateMode) {
    LSMapPickerCoordinateModeStatic = 0,
    LSMapPickerCoordinateModeRoute = 1
};

typedef NS_ENUM(NSInteger, LSRoutePlacementPhase) {
    LSRoutePlacementPhaseStart = 0,
    LSRoutePlacementPhaseDestination = 1
};

@interface LSStartAnnotation : MKPointAnnotation
@end

@interface LSDestinationAnnotation : MKPointAnnotation
@end

@interface MapPickerViewController () <UIGestureRecognizerDelegate, UITextFieldDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *tableHeaderContainer;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UIStackView *statusStackView;
@property (nonatomic, strong) UIView *statusDot;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *pillStopLabel;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UIActivityIndicatorView *searchSpinner;
@property (nonatomic, strong) MKLocalSearchCompleter *searchCompleter;
@property (nonatomic, strong) NSArray<MKLocalSearchCompletion *> *searchCompletions;
@property (nonatomic, strong) UIView *suggestionsPanel;
@property (nonatomic, strong) UITableView *suggestionsTableView;
@property (nonatomic, strong) NSLayoutConstraint *suggestionsHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *searchBarHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *searchBarBottomConstraint;
@property (nonatomic, strong) NSLayoutConstraint *coordinateModeHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *coordinateModeBottomConstraint;
@property (nonatomic, assign) BOOL searchSuggestionsVisible;
@property (nonatomic, strong) UIView *mapContainer;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UILabel *mapHintLabel;
@property (nonatomic, strong) UIActivityIndicatorView *mapSpinner;
@property (nonatomic, strong) UISegmentedControl *panelTabSegment;
@property (nonatomic, strong) UISegmentedControl *coordinateModeSegment;
@property (nonatomic, strong) UITapGestureRecognizer *mapTapGesture;
@property (nonatomic, strong) UILongPressGestureRecognizer *mapLongPressGesture;

@property (nonatomic, strong) UIButton *bookmarkSaveButton;

@property (nonatomic, strong) UISwitch *fluctuationSwitch;
@property (nonatomic, strong) UISlider *fluctuationRadiusSlider;
@property (nonatomic, strong) UILabel *fluctuationRadiusLabel;
@property (nonatomic, strong) UISwitch *keepLastSpoofSwitch;
@property (nonatomic, strong) UISwitch *showRealLocationSwitch;
@property (nonatomic, strong) UISwitch *darkModeSwitch;
@property (nonatomic, strong) UITableViewCell *darkModeCell;
@property (nonatomic, strong) UISegmentedControl *themeSegmentedControl;
@property (nonatomic, strong) UITableViewCell *themeSelectionCell;
@property (nonatomic, strong, nullable) MKCircle *driftCircleOverlay;
@property (nonatomic, strong) UIButton *snapStartButton;
@property (nonatomic, strong) NSLayoutConstraint *mapHeightConstraint;

@property (nonatomic, strong) UITextField *latitudeField;
@property (nonatomic, strong) UITextField *longitudeField;
@property (nonatomic, strong) UITextField *altitudeField;
@property (nonatomic, strong) UISlider *headingSlider;
@property (nonatomic, strong) UILabel *headingValueLabel;
@property (nonatomic, strong) UILabel *headingDirectionLabel;

@property (nonatomic, strong) UIButton *applyButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UIButton *stopButton;

// Hero Status Card (Big Active/Inactive indicator & switch)
@property (nonatomic, strong) UITableViewCell *heroStatusCell;
@property (nonatomic, strong) UIView *heroStatusDot;
@property (nonatomic, strong) UILabel *heroStatusTitleLabel;
@property (nonatomic, strong) UILabel *heroStatusSubtitleLabel;
@property (nonatomic, strong) UISwitch *heroStatusSwitch;

// Retained static cells for Static Mode
@property (nonatomic, strong) UITableViewCell *previewCell;
@property (nonatomic, strong) UILabel *previewCoordLabel;
@property (nonatomic, strong) UITableViewCell *latitudeCell;
@property (nonatomic, strong) UITableViewCell *longitudeCell;
@property (nonatomic, strong) UITableViewCell *altitudeCell;
@property (nonatomic, strong) UITableViewCell *headingCell;
@property (nonatomic, strong) UITableViewCell *fluctuationCell;
@property (nonatomic, strong) UITableViewCell *fluctuationRadiusCell;
@property (nonatomic, strong) UITableViewCell *keepLastSpoofCell;
@property (nonatomic, strong) UITableViewCell *showRealLocationCell;
@property (nonatomic, strong) UITableViewCell *floatingButtonCell;
@property (nonatomic, strong) UISwitch *floatingButtonSwitch;
@property (nonatomic, strong) UITableViewCell *applyButtonCell;
@property (nonatomic, strong) UITableViewCell *stopButtonCell;
@property (nonatomic, strong) UITableViewCell *cancelButtonCell;


// Retained static cells for Route Mode
@property (nonatomic, strong) UITableViewCell *routeStartCell;
@property (nonatomic, strong) UILabel *routeStartSubLabel;
@property (nonatomic, strong) UITableViewCell *routeDestCell;
@property (nonatomic, strong) UILabel *routeDestSubLabel;
@property (nonatomic, strong) UITableViewCell *routeGetDirectionsCell;
@property (nonatomic, strong) UITableViewCell *routeTransportCell;
@property (nonatomic, strong) UITableViewCell *routeCustomSpeedCell;
@property (nonatomic, strong) UITableViewCell *routePlaybackCell;
@property (nonatomic, strong) UITableViewCell *routeCancelCell;

@property (nonatomic, strong) MKPointAnnotation *pinAnnotation;
@property (nonatomic, strong, nullable) LSStartAnnotation *startAnnotation;
@property (nonatomic, strong, nullable) LSDestinationAnnotation *destinationAnnotation;
@property (nonatomic, assign) LSRoutePlacementPhase routePlacementPhase;
@property (nonatomic, strong, nullable) MKRoute *fetchedRoute;
@property (nonatomic, strong, nullable) MKPolyline *routePolyline;
@property (nonatomic, strong) UIButton *getRouteButton;
@property (nonatomic, strong) UISegmentedControl *transportModeSegment;
@property (nonatomic, strong) UITextField *customSpeedField;
@property (nonatomic, strong) UIButton *playRouteButton;
@property (nonatomic, strong) UIActivityIndicatorView *routeSpinner;
@property (nonatomic, strong) UIButton *pauseRouteButton;
@property (nonatomic, strong) UIButton *stopRouteButton;

@property (nonatomic, assign) CLLocationCoordinate2D selectedCoordinate;
@property (nonatomic, assign) BOOL hasSelectedCoordinate;
@property (nonatomic, assign) BOOL mapConfigured;
@property (nonatomic, assign) BOOL suppressFieldSync;
@property (nonatomic, assign) LSMapPickerPanelTab panelTab;
@property (nonatomic, assign) LSMapPickerCoordinateMode coordinateMode;
@property (nonatomic, assign) BOOL bookmarksEditMode;

+ (UIImage *)systemImageNamedWithFallback:(NSString *)name configuration:(nullable UIImageConfiguration *)config;
+ (UIView *)iconBadgeWithSymbolName:(NSString *)symbolName backgroundColor:(UIColor *)bgColor;
- (void)refreshStatusPill;
- (void)syncFieldsFromCoordinate;
- (void)updateCoordinateLabel;
- (void)movePinToCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated;
- (void)updatePinOnMapAnimated:(BOOL)animated;
- (nullable NSNumber *)ls_parsedCoordinateComponentFromText:(NSString *)text;
- (BOOL)applyFieldsToCoordinate;
- (BOOL)applyAltitudeField;
- (void)updateHeadingLabel;
- (void)showInvalidCoordinateFeedback;
- (void)playApplyHaptic;
- (void)playRouteSuccessHaptic;
- (void)playRouteFailureHaptic;
- (void)playBookmarkSavedHaptic;
- (void)playSimulationStopHaptic;
- (void)dismissKeyboard;
- (void)toggleSignForActiveField;
- (void)handleMapTap:(UITapGestureRecognizer *)gesture;
- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)handleHeadingSliderChanged:(UISlider *)sender;
- (void)handleApply;
- (void)handleCancel;
- (void)handleStopSpoofing;
- (void)updateHeroStatusCell;
- (void)handleHeroStatusSwitchToggled:(UISwitch *)sender;
- (void)handleFluctuationRadiusSliderChanged:(UISlider *)sender;
- (void)handleCheckForUpdatesTapped;
- (void)handleDarkModeToggled:(UISwitch *)sender;
- (void)handleThemeChanged:(UISegmentedControl *)sender;
- (void)updateDriftRadiusOverlay;
- (void)ls_updateTableHeaderLayout;

@end


@interface MapPickerViewController (LSRouteUI) <LSRouteSimulatorDelegate>

- (void)buildRouteControls;
- (void)handleGetRouteTapped;
- (void)handleSnapStartToCurrentLocation;
- (void)dismissCustomSpeedKeyboard;
- (void)ls_handleRouteMapTap:(CLLocationCoordinate2D)coordinate;
- (void)updateCoordinateModeVisibility;
- (void)restoreSimulationUIIfNeeded;
- (void)restoreRouteUIFromSimulator;
- (MKOverlayRenderer *)ls_rendererForMapOverlay:(id<MKOverlay>)overlay;
- (nullable MKAnnotationView *)ls_viewForRouteAnnotation:(id<MKAnnotation>)annotation;
- (void)ls_routeAnnotationDragEnded:(MKAnnotationView *)view;

- (NSInteger)ls_routeNumberOfSections;
- (NSInteger)ls_routeNumberOfRowsInSection:(NSInteger)section;
- (nullable NSString *)ls_routeTitleForHeaderInSection:(NSInteger)section;
- (UITableViewCell *)ls_routeCellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)ls_routeDidSelectRowAtIndexPath:(NSIndexPath *)indexPath;

@end

@interface MapPickerViewController (LSBookmarksUI)

- (void)buildBookmarksPanel;
- (void)updatePanelTabVisibility;
- (void)handlePanelTabChanged:(UISegmentedControl *)sender;
- (void)handleCoordinateModeChanged:(UISegmentedControl *)sender;
- (void)handleBookmarkSaveTapped;
- (void)presentSaveBookmarkAlertWithSuggestedName:(nullable NSString *)name coordinate:(CLLocationCoordinate2D)coordinate;
- (NSInteger)ls_bookmarksNumberOfSections;
- (NSInteger)ls_bookmarksNumberOfRowsInSection:(NSInteger)section;
- (nullable NSString *)ls_bookmarksTitleForHeaderInSection:(NSInteger)section;
- (UITableViewCell *)ls_bookmarksCellForRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)ls_bookmarksDidSelectRowAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)ls_bookmarksCanEditRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)ls_bookmarksCommitDeleteAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)ls_bookmarksCanMoveRowAtIndexPath:(NSIndexPath *)indexPath;
- (void)ls_bookmarksMoveFromIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination;
- (nullable UIView *)ls_bookmarksHeaderForSection:(NSInteger)section;
- (void)ls_presentStaticMapActionSheetAtCoordinate:(CLLocationCoordinate2D)coordinate;

@end

NS_ASSUME_NONNULL_END
