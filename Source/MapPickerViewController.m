#import "MapPickerViewController.h"
#import "MapPickerViewController+Private.h"
#import "LocationSpoofer.h"
#import "OverlayWindow.h"
#import "PersistenceManager.h"
#import "RouteSimulator.h"
#import "LSUpdateChecker.h"

#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

static const CGFloat kLSCornerRadius = 16.0;
static const CGFloat kLSHorizontalInset = 16.0;
static const CGFloat kLSSuggestionRowHeight = 48.0;
static const CGFloat kLSSuggestionMaxHeight = 200.0;
static const CGFloat kLSMapHeight = 220.0;

@interface MapPickerViewController () <MKMapViewDelegate, UISearchBarDelegate, UITextFieldDelegate, MKLocalSearchCompleterDelegate, UITableViewDataSource, UITableViewDelegate>
@end

@implementation MapPickerViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.hasSelectedCoordinate = NO;

    PersistenceManager *store = [PersistenceManager shared];
    if ([store isSpoofingEnabled] || [store hasStoredCoordinate]) {
        self.selectedCoordinate = [store spoofCoordinate];
        self.hasSelectedCoordinate = YES;
    } else if (store.hasRealCoordinate && CLLocationCoordinate2DIsValid(store.lastRealCoordinate) && (store.lastRealCoordinate.latitude != 0 || store.lastRealCoordinate.longitude != 0)) {
        self.selectedCoordinate = store.lastRealCoordinate;
        self.hasSelectedCoordinate = YES;
    } else {
        LSSetHooksBypassed(YES);
        CLLocationManager *locManager = [[CLLocationManager alloc] init];
        CLLocation *loc = locManager.location;
        LSSetHooksBypassed(NO);
        if (loc && CLLocationCoordinate2DIsValid(loc.coordinate) && (loc.coordinate.latitude != 0 || loc.coordinate.longitude != 0)) {
            self.selectedCoordinate = loc.coordinate;
            self.hasSelectedCoordinate = YES;
            store.lastRealCoordinate = loc.coordinate;
            store.hasRealCoordinate = YES;
        } else {
            self.selectedCoordinate = CLLocationCoordinate2DMake(0, 0);
            self.hasSelectedCoordinate = NO;
        }
    }
    self.panelTab = LSMapPickerPanelTabMap;
    self.coordinateMode = LSMapPickerCoordinateModeStatic;

    [self buildInterface];
    [self buildStaticCells];
    [self buildRouteControls];
    [self buildBookmarksPanel];
    [self configureKeyboardToolbar];
    [self configureSearchCompleter];
    [self restoreSimulationUIIfNeeded];
    [self refreshStatusPill];
    [self syncFieldsFromCoordinate];

    self.altitudeField.text = [NSString stringWithFormat:@"%.0f m", store.altitude];
    self.headingSlider.value = (float)store.heading;
    [self updateHeadingLabel];
    [self updatePanelTabVisibility];

    self.fluctuationSwitch.on = store.fluctuationEnabled;
    self.fluctuationRadiusSlider.value = (float)store.fluctuationRadius;
    self.fluctuationRadiusLabel.text = [NSString stringWithFormat:@"%.0f m", store.fluctuationRadius];
    self.keepLastSpoofSwitch.on = store.keepLastSpoof;
    self.showRealLocationSwitch.on = store.showRealLocation;
    [self updateHeroStatusCell];


    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ls_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ls_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self ls_updateTableHeaderLayout];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    _searchCompleter.delegate = nil;
    _mapView.delegate = nil;
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
    _suggestionsTableView.delegate = nil;
    _suggestionsTableView.dataSource = nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    LSSetHooksBypassed(YES);
    [LSOverlayManager setMapPickerVisible:YES];
    [self refreshStatusPill];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    LSSetHooksBypassed(YES);
    [self configureMapIfNeeded];
    [LSUpdateChecker checkForUpdatesAutomatically];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [LSOverlayManager restoreMapPickerSessionState];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [LSOverlayManager restoreMapPickerSessionState];
}

#pragma mark - SF Symbol Fallbacks

+ (UIImage *)systemImageNamedWithFallback:(NSString *)name configuration:(nullable UIImageConfiguration *)config {
    UIImage *img = config ? [UIImage systemImageNamed:name withConfiguration:config] : [UIImage systemImageNamed:name];
    if (img) return img;

    static NSDictionary<NSString *, NSString *> *fallbacks = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fallbacks = @{
            @"globe.americas.fill": @"globe",
            @"mountain.2.fill": @"triangle.fill",
            @"circle.dashed": @"circle",
            @"location.fill.viewfinder": @"location.fill",
            @"flag.checkered": @"flag.fill",
            @"arrow.triangle.turn.up.right.diamond.fill": @"arrow.turn.up.right"
        };
    });

    NSString *fallbackName = fallbacks[name];
    if (fallbackName) {
        return config ? [UIImage systemImageNamed:fallbackName withConfiguration:config] : [UIImage systemImageNamed:fallbackName];
    }
    return nil;
}

+ (UIView *)iconBadgeWithSymbolName:(NSString *)symbolName backgroundColor:(UIColor *)bgColor {
    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30.0, 30.0)];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = bgColor;
    badge.layer.cornerRadius = 7.0;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.clipsToBounds = YES;

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIFontWeightSemibold];
    UIImage *image = [self systemImageNamedWithFallback:symbolName configuration:config];
    UIImageView *iv = [[UIImageView alloc] initWithImage:image];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.tintColor = UIColor.whiteColor;
    iv.contentMode = UIViewContentModeCenter;
    [badge addSubview:iv];

    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:30.0],
        [badge.heightAnchor constraintEqualToConstant:30.0],
        [iv.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [iv.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor]
    ]];
    return badge;
}

#pragma mark - Interface Setup

- (void)buildInterface {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.tableView.showsVerticalScrollIndicator = YES;
    self.tableView.delaysContentTouches = NO;
    [self.view addSubview:self.tableView];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor]
    ]];

    [self buildHeaderAndMap];
    [self buildControls];

    UIView *tableFooter = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 54.0)];
    UIButton *updateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    updateButton.translatesAutoresizingMaskIntoConstraints = NO;
    updateButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    [updateButton setTitle:[NSString stringWithFormat:@"LSpoof v%@ · Check for Updates", [LSUpdateChecker currentVersion]] forState:UIControlStateNormal];
    [updateButton setTitleColor:UIColor.secondaryLabelColor forState:UIControlStateNormal];
    [updateButton addTarget:self action:@selector(handleCheckForUpdatesTapped) forControlEvents:UIControlEventTouchUpInside];
    [tableFooter addSubview:updateButton];

    [NSLayoutConstraint activateConstraints:@[
        [updateButton.centerXAnchor constraintEqualToAnchor:tableFooter.centerXAnchor],
        [updateButton.centerYAnchor constraintEqualToAnchor:tableFooter.centerYAnchor],
        [updateButton.heightAnchor constraintEqualToConstant:36.0]
    ]];
    self.tableView.tableFooterView = tableFooter;
}

- (void)buildHeaderAndMap {
    UIView *tableHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 420.0)];
    tableHeader.backgroundColor = UIColor.clearColor;
    self.tableHeaderContainer = tableHeader;

    // Header title row
    self.headerView = [[UIView alloc] init];
    self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [tableHeader addSubview:self.headerView];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"Location Spoofer";
    self.titleLabel.font = [UIFont systemFontOfSize:26.0 weight:UIFontWeightBold];
    self.titleLabel.textColor = UIColor.labelColor;
    self.titleLabel.accessibilityTraits = UIAccessibilityTraitHeader;
    [self.headerView addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"Choose where apps think you are";
    self.subtitleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
    self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
    [self.headerView addSubview:self.subtitleLabel];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageConfiguration *closeConfig = [UIImageSymbolConfiguration configurationWithPointSize:26.0 weight:UIFontWeightRegular];
    UIImage *closeImage = [MapPickerViewController systemImageNamedWithFallback:@"xmark.circle.fill" configuration:closeConfig];
    [self.closeButton setImage:closeImage forState:UIControlStateNormal];
    self.closeButton.tintColor = UIColor.tertiaryLabelColor;
    self.closeButton.accessibilityLabel = @"Close";
    [self.closeButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.closeButton];

    // Status pill with collapsing stack view
    self.statusPill = [[UIView alloc] init];
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPill.backgroundColor = [UIColor.tertiarySystemFillColor colorWithAlphaComponent:0.9];
    self.statusPill.layer.cornerRadius = 14.0;
    self.statusPill.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusPill.userInteractionEnabled = YES;
    [self.headerView addSubview:self.statusPill];

    self.statusDot = [[UIView alloc] init];
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusDot.layer.cornerRadius = 4.0;
    self.statusDot.backgroundColor = UIColor.systemOrangeColor;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;

    self.pillStopLabel = [[UILabel alloc] init];
    self.pillStopLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pillStopLabel.text = @"Stop";
    self.pillStopLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    self.pillStopLabel.textColor = UIColor.systemRedColor;
    self.pillStopLabel.hidden = YES;

    self.statusStackView = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusDot, self.statusLabel, self.pillStopLabel]];
    self.statusStackView.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusStackView.axis = UILayoutConstraintAxisHorizontal;
    self.statusStackView.alignment = UIStackViewAlignmentCenter;
    self.statusStackView.spacing = 6.0;
    self.statusStackView.layoutMarginsRelativeArrangement = YES;
    self.statusStackView.layoutMargins = UIEdgeInsetsMake(6.0, 10.0, 6.0, 12.0);
    [self.statusPill addSubview:self.statusStackView];

    UITapGestureRecognizer *pillTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleStatusPillTapped)];
    [self.statusPill addGestureRecognizer:pillTap];

    // Search bar
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.placeholder = @"Search city, address, or landmark";
    self.searchBar.delegate = self;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    self.searchBar.backgroundColor = UIColor.clearColor;
    self.searchBar.tintColor = UIColor.systemBlueColor;
    self.searchBar.layoutMargins = UIEdgeInsetsZero;
    UITextField *tf = self.searchBar.searchTextField;
    tf.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    tf.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    tf.layer.cornerRadius = 12.0;
    tf.clipsToBounds = YES;
    [tableHeader addSubview:self.searchBar];

    self.searchSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.searchSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchSpinner.hidesWhenStopped = YES;
    [tableHeader addSubview:self.searchSpinner];

    // Map container
    self.mapContainer = [[UIView alloc] init];
    self.mapContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapContainer.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.mapContainer.layer.cornerRadius = kLSCornerRadius;
    self.mapContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapContainer.clipsToBounds = YES;
    self.mapContainer.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.mapContainer.layer.borderColor = UIColor.separatorColor.CGColor;
    [tableHeader addSubview:self.mapContainer];

    self.mapView = [[MKMapView alloc] initWithFrame:CGRectZero];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = ![[PersistenceManager shared] isSpoofingEnabled];
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    self.mapView.layoutMargins = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    [self.mapContainer addSubview:self.mapView];

    self.mapTapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    self.mapLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    self.mapLongPressGesture.minimumPressDuration = 0.5;
    self.mapLongPressGesture.delegate = self;
    [self.mapTapGesture requireGestureRecognizerToFail:self.mapLongPressGesture];
    [self.mapView addGestureRecognizer:self.mapTapGesture];
    [self.mapView addGestureRecognizer:self.mapLongPressGesture];

    // Map hint badge
    self.mapHintLabel = [[UILabel alloc] init];
    self.mapHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapHintLabel.text = @"  Tap map or drag pin  ";
    self.mapHintLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    self.mapHintLabel.textColor = UIColor.labelColor;
    self.mapHintLabel.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.92];
    self.mapHintLabel.layer.cornerRadius = 12.0;
    self.mapHintLabel.layer.cornerCurve = kCACornerCurveContinuous;
    self.mapHintLabel.clipsToBounds = YES;
    self.mapHintLabel.textAlignment = NSTextAlignmentCenter;
    [self.mapContainer addSubview:self.mapHintLabel];

    self.mapSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.mapSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapSpinner.hidesWhenStopped = YES;
    self.mapSpinner.color = UIColor.systemGrayColor;
    [self.mapContainer addSubview:self.mapSpinner];

    // Floating Search Suggestions Overlay
    self.suggestionsPanel = [[UIView alloc] init];
    self.suggestionsPanel.translatesAutoresizingMaskIntoConstraints = NO;
    self.suggestionsPanel.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.suggestionsPanel.layer.cornerRadius = 14.0;
    self.suggestionsPanel.layer.cornerCurve = kCACornerCurveContinuous;
    self.suggestionsPanel.clipsToBounds = YES;
    self.suggestionsPanel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.suggestionsPanel.layer.borderColor = UIColor.separatorColor.CGColor;
    self.suggestionsPanel.hidden = YES;
    self.suggestionsPanel.alpha = 0.0;
    [tableHeader addSubview:self.suggestionsPanel];

    self.suggestionsTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.suggestionsTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.suggestionsTableView.dataSource = self;
    self.suggestionsTableView.delegate = self;
    self.suggestionsTableView.separatorInset = UIEdgeInsetsMake(0.0, 16.0, 0.0, 16.0);
    self.suggestionsTableView.rowHeight = kLSSuggestionRowHeight;
    self.suggestionsTableView.backgroundColor = UIColor.clearColor;
    self.suggestionsTableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeNone;
    [self.suggestionsTableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"LSSearchSuggestionCell"];
    [self.suggestionsPanel addSubview:self.suggestionsTableView];

    // Tab segment: [Map | Bookmarks]
    self.panelTabSegment = [[UISegmentedControl alloc] initWithItems:@[@"Map", @"Bookmarks"]];
    self.panelTabSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.panelTabSegment.selectedSegmentIndex = LSMapPickerPanelTabMap;
    [self.panelTabSegment addTarget:self action:@selector(handlePanelTabChanged:) forControlEvents:UIControlEventValueChanged];
    [tableHeader addSubview:self.panelTabSegment];

    // Mode segment: [Static | Route]
    self.coordinateModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Static", @"Route"]];
    self.coordinateModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.coordinateModeSegment.selectedSegmentIndex = LSMapPickerCoordinateModeStatic;
    [self.coordinateModeSegment addTarget:self action:@selector(handleCoordinateModeChanged:) forControlEvents:UIControlEventValueChanged];
    [tableHeader addSubview:self.coordinateModeSegment];

    // Header layout constraints
    self.searchBarHeightConstraint = [self.searchBar.heightAnchor constraintEqualToConstant:48.0];
    self.searchBarBottomConstraint = [self.mapContainer.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:6.0];
    self.coordinateModeHeightConstraint = [self.coordinateModeSegment.heightAnchor constraintEqualToConstant:32.0];
    self.coordinateModeBottomConstraint = [self.coordinateModeSegment.bottomAnchor constraintEqualToAnchor:tableHeader.bottomAnchor constant:-8.0];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerView.topAnchor constraintEqualToAnchor:tableHeader.topAnchor constant:8.0],
        [self.headerView.leadingAnchor constraintEqualToAnchor:tableHeader.leadingAnchor constant:kLSHorizontalInset],
        [self.headerView.trailingAnchor constraintEqualToAnchor:tableHeader.trailingAnchor constant:-kLSHorizontalInset],

        [self.titleLabel.topAnchor constraintEqualToAnchor:self.headerView.topAnchor],
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.closeButton.leadingAnchor constant:-12.0],

        [self.closeButton.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.closeButton.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor],
        [self.closeButton.widthAnchor constraintEqualToConstant:32.0],
        [self.closeButton.heightAnchor constraintEqualToConstant:32.0],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:3.0],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor],

        [self.statusPill.topAnchor constraintEqualToAnchor:self.subtitleLabel.bottomAnchor constant:10.0],
        [self.statusPill.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor],
        [self.statusPill.bottomAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],

        [self.statusDot.widthAnchor constraintEqualToConstant:8.0],
        [self.statusDot.heightAnchor constraintEqualToConstant:8.0],

        [self.statusStackView.topAnchor constraintEqualToAnchor:self.statusPill.topAnchor],
        [self.statusStackView.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor],
        [self.statusStackView.trailingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor],
        [self.statusStackView.bottomAnchor constraintEqualToAnchor:self.statusPill.bottomAnchor],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:10.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:tableHeader.leadingAnchor constant:kLSHorizontalInset - 6.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:tableHeader.trailingAnchor constant:-(kLSHorizontalInset - 6.0)],
        self.searchBarHeightConstraint,

        [self.searchSpinner.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor],
        [self.searchSpinner.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor constant:-16.0],

        self.searchBarBottomConstraint,
        [self.mapContainer.leadingAnchor constraintEqualToAnchor:tableHeader.leadingAnchor constant:kLSHorizontalInset],
        [self.mapContainer.trailingAnchor constraintEqualToAnchor:tableHeader.trailingAnchor constant:-kLSHorizontalInset],
        [self.mapContainer.heightAnchor constraintEqualToConstant:kLSMapHeight],

        [self.mapView.topAnchor constraintEqualToAnchor:self.mapContainer.topAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.mapContainer.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.mapContainer.trailingAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor],

        [self.mapHintLabel.bottomAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor constant:-10.0],
        [self.mapHintLabel.centerXAnchor constraintEqualToAnchor:self.mapContainer.centerXAnchor],

        [self.mapSpinner.centerXAnchor constraintEqualToAnchor:self.mapContainer.centerXAnchor],
        [self.mapSpinner.centerYAnchor constraintEqualToAnchor:self.mapContainer.centerYAnchor],

        [self.suggestionsPanel.topAnchor constraintEqualToAnchor:self.mapContainer.topAnchor constant:4.0],
        [self.suggestionsPanel.leadingAnchor constraintEqualToAnchor:self.mapContainer.leadingAnchor constant:4.0],
        [self.suggestionsPanel.trailingAnchor constraintEqualToAnchor:self.mapContainer.trailingAnchor constant:-4.0],

        [self.suggestionsTableView.topAnchor constraintEqualToAnchor:self.suggestionsPanel.topAnchor],
        [self.suggestionsTableView.leadingAnchor constraintEqualToAnchor:self.suggestionsPanel.leadingAnchor],
        [self.suggestionsTableView.trailingAnchor constraintEqualToAnchor:self.suggestionsPanel.trailingAnchor],
        [self.suggestionsTableView.bottomAnchor constraintEqualToAnchor:self.suggestionsPanel.bottomAnchor],

        [self.panelTabSegment.topAnchor constraintEqualToAnchor:self.mapContainer.bottomAnchor constant:12.0],
        [self.panelTabSegment.leadingAnchor constraintEqualToAnchor:tableHeader.leadingAnchor constant:kLSHorizontalInset],
        [self.panelTabSegment.trailingAnchor constraintEqualToAnchor:tableHeader.trailingAnchor constant:-kLSHorizontalInset],
        [self.panelTabSegment.heightAnchor constraintEqualToConstant:34.0],

        [self.coordinateModeSegment.topAnchor constraintEqualToAnchor:self.panelTabSegment.bottomAnchor constant:8.0],
        [self.coordinateModeSegment.leadingAnchor constraintEqualToAnchor:tableHeader.leadingAnchor constant:kLSHorizontalInset],
        [self.coordinateModeSegment.trailingAnchor constraintEqualToAnchor:tableHeader.trailingAnchor constant:-kLSHorizontalInset],
        self.coordinateModeHeightConstraint,
        self.coordinateModeBottomConstraint
    ]];

    self.suggestionsHeightConstraint = [self.suggestionsPanel.heightAnchor constraintEqualToConstant:0.0];
    self.suggestionsHeightConstraint.active = YES;

    self.tableView.tableHeaderView = tableHeader;
    [self ls_updateTableHeaderLayout];
}

- (void)ls_updateTableHeaderLayout {
    UIView *header = self.tableView.tableHeaderView;
    if (!header) return;

    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) width = self.view.bounds.size.width;
    if (width <= 0) return;

    CGRect frame = header.frame;
    frame.size.width = width;
    header.frame = frame;

    [header setNeedsLayout];
    [header layoutIfNeeded];

    CGFloat targetHeight = [header systemLayoutSizeFittingSize:CGSizeMake(width, 0)
                                 withHorizontalFittingPriority:UILayoutPriorityRequired
                                       verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;

    if (fabs(header.frame.size.height - targetHeight) > 0.5) {
        frame.size.height = targetHeight;
        header.frame = frame;
        self.tableView.tableHeaderView = header;
    }
}

- (void)buildControls {
    // Latitude text field
    self.latitudeField = [self ls_createInputTextFieldWithPlaceholder:@"e.g. 37.774900"];
    [self.latitudeField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    // Longitude text field
    self.longitudeField = [self ls_createInputTextFieldWithPlaceholder:@"e.g. -122.419400"];
    [self.longitudeField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    // Altitude text field
    self.altitudeField = [self ls_createInputTextFieldWithPlaceholder:@"e.g. 0 m"];
    [self.altitudeField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    // Heading slider and labels
    self.headingValueLabel = [[UILabel alloc] init];
    self.headingValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
    self.headingValueLabel.textColor = UIColor.secondaryLabelColor;
    self.headingValueLabel.textAlignment = NSTextAlignmentRight;

    self.headingSlider = [[UISlider alloc] init];
    self.headingSlider.minimumValue = 0.0f;
    self.headingSlider.maximumValue = 359.0f;
    self.headingSlider.tintColor = UIColor.systemIndigoColor;
    [self.headingSlider addTarget:self action:@selector(handleHeadingSliderChanged:) forControlEvents:UIControlEventValueChanged];

    // Fluctuation controls
    self.fluctuationSwitch = [[UISwitch alloc] init];
    [self.fluctuationSwitch addTarget:self action:@selector(handleFluctuationToggle) forControlEvents:UIControlEventValueChanged];

    self.fluctuationRadiusLabel = [[UILabel alloc] init];
    self.fluctuationRadiusLabel.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightSemibold];
    self.fluctuationRadiusLabel.textColor = UIColor.secondaryLabelColor;
    self.fluctuationRadiusLabel.textAlignment = NSTextAlignmentRight;

    self.fluctuationRadiusSlider = [[UISlider alloc] init];
    self.fluctuationRadiusSlider.minimumValue = 5.0f;
    self.fluctuationRadiusSlider.maximumValue = 150.0f;
    self.fluctuationRadiusSlider.tintColor = UIColor.systemPurpleColor;
    [self.fluctuationRadiusSlider addTarget:self action:@selector(handleFluctuationRadiusSliderChanged:) forControlEvents:UIControlEventValueChanged];


    // Other switches
    self.keepLastSpoofSwitch = [[UISwitch alloc] init];
    [self.keepLastSpoofSwitch addTarget:self action:@selector(handleKeepLastSpoofToggle) forControlEvents:UIControlEventValueChanged];

    self.showRealLocationSwitch = [[UISwitch alloc] init];
    [self.showRealLocationSwitch addTarget:self action:@selector(handleShowRealLocationToggle) forControlEvents:UIControlEventValueChanged];

    // Action buttons
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.applyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.applyButton setTitle:@"  Apply Location" forState:UIControlStateNormal];
    [self.applyButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.applyButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    UIImage *checkIcon = [MapPickerViewController systemImageNamedWithFallback:@"checkmark.circle.fill" configuration:[UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIFontWeightBold]];
    [self.applyButton setImage:checkIcon forState:UIControlStateNormal];
    self.applyButton.tintColor = UIColor.whiteColor;
    self.applyButton.backgroundColor = UIColor.systemBlueColor;
    self.applyButton.layer.cornerRadius = 14.0;
    self.applyButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.applyButton addTarget:self action:@selector(handleApply) forControlEvents:UIControlEventTouchUpInside];

    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stopButton setTitle:@"  Stop Spoofing" forState:UIControlStateNormal];
    [self.stopButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    self.stopButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    UIImage *stopIcon = [MapPickerViewController systemImageNamedWithFallback:@"stop.circle.fill" configuration:[UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIFontWeightBold]];
    [self.stopButton setImage:stopIcon forState:UIControlStateNormal];
    self.stopButton.tintColor = UIColor.systemRedColor;
    self.stopButton.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    self.stopButton.layer.cornerRadius = 14.0;
    self.stopButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.stopButton.layer.borderWidth = 1.0;
    self.stopButton.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.4].CGColor;
    [self.stopButton addTarget:self action:@selector(handleStopSpoofing) forControlEvents:UIControlEventTouchUpInside];

    self.cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.cancelButton setTitleColor:UIColor.secondaryLabelColor forState:UIControlStateNormal];
    self.cancelButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    self.cancelButton.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.cancelButton.layer.cornerRadius = 14.0;
    self.cancelButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.cancelButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
}

- (UITextField *)ls_createInputTextFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholder;
    field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightRegular];
    field.textColor = UIColor.labelColor;
    field.textAlignment = NSTextAlignmentRight;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.delegate = self;
    return field;
}

#pragma mark - Retained Static Cells Setup

- (void)buildStaticCells {
    // 0: Hero Status Card (Big Active / Inactive indicator & switch)
    self.heroStatusCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.heroStatusCell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.heroStatusCell.selectionStyle = UITableViewCellSelectionStyleNone;

    self.heroStatusDot = [[UIView alloc] init];
    self.heroStatusDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroStatusDot.layer.cornerRadius = 8.0;
    self.heroStatusDot.backgroundColor = UIColor.systemOrangeColor;
    [self.heroStatusCell.contentView addSubview:self.heroStatusDot];

    self.heroStatusTitleLabel = [[UILabel alloc] init];
    self.heroStatusTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroStatusTitleLabel.text = @"Spoofing Inactive";
    self.heroStatusTitleLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightBold];
    self.heroStatusTitleLabel.textColor = UIColor.labelColor;
    [self.heroStatusCell.contentView addSubview:self.heroStatusTitleLabel];

    self.heroStatusSubtitleLabel = [[UILabel alloc] init];
    self.heroStatusSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroStatusSubtitleLabel.text = @"Using device native GPS · Toggle to activate";
    self.heroStatusSubtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
    self.heroStatusSubtitleLabel.textColor = UIColor.secondaryLabelColor;
    [self.heroStatusCell.contentView addSubview:self.heroStatusSubtitleLabel];

    self.heroStatusSwitch = [[UISwitch alloc] init];
    self.heroStatusSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.heroStatusSwitch addTarget:self action:@selector(handleHeroStatusSwitchToggled:) forControlEvents:UIControlEventValueChanged];
    [self.heroStatusCell.contentView addSubview:self.heroStatusSwitch];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroStatusDot.leadingAnchor constraintEqualToAnchor:self.heroStatusCell.contentView.leadingAnchor constant:16.0],
        [self.heroStatusDot.centerYAnchor constraintEqualToAnchor:self.heroStatusCell.contentView.centerYAnchor],
        [self.heroStatusDot.widthAnchor constraintEqualToConstant:16.0],
        [self.heroStatusDot.heightAnchor constraintEqualToConstant:16.0],

        [self.heroStatusTitleLabel.leadingAnchor constraintEqualToAnchor:self.heroStatusDot.trailingAnchor constant:12.0],
        [self.heroStatusTitleLabel.topAnchor constraintEqualToAnchor:self.heroStatusCell.contentView.topAnchor constant:14.0],
        [self.heroStatusTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.heroStatusSwitch.leadingAnchor constant:-12.0],

        [self.heroStatusSubtitleLabel.leadingAnchor constraintEqualToAnchor:self.heroStatusTitleLabel.leadingAnchor],
        [self.heroStatusSubtitleLabel.topAnchor constraintEqualToAnchor:self.heroStatusTitleLabel.bottomAnchor constant:3.0],
        [self.heroStatusSubtitleLabel.bottomAnchor constraintEqualToAnchor:self.heroStatusCell.contentView.bottomAnchor constant:-14.0],
        [self.heroStatusSubtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.heroStatusSwitch.leadingAnchor constant:-12.0],

        [self.heroStatusSwitch.trailingAnchor constraintEqualToAnchor:self.heroStatusCell.contentView.trailingAnchor constant:-16.0],
        [self.heroStatusSwitch.centerYAnchor constraintEqualToAnchor:self.heroStatusCell.contentView.centerYAnchor]
    ]];

    // 1: Target Coordinate Preview & Bookmark Cell
    self.previewCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    self.previewCell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.previewCell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *previewBadge = [MapPickerViewController iconBadgeWithSymbolName:@"mappin.and.ellipse" backgroundColor:UIColor.systemRedColor];
    [self.previewCell.contentView addSubview:previewBadge];


    UILabel *previewTitle = [[UILabel alloc] init];
    previewTitle.translatesAutoresizingMaskIntoConstraints = NO;
    previewTitle.text = @"Target Coordinate";
    previewTitle.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    previewTitle.textColor = UIColor.labelColor;
    [self.previewCell.contentView addSubview:previewTitle];

    self.previewCoordLabel = [[UILabel alloc] init];
    self.previewCoordLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.previewCoordLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    self.previewCoordLabel.textColor = UIColor.secondaryLabelColor;
    [self.previewCell.contentView addSubview:self.previewCoordLabel];

    UIButton *bmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    bmBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *bmIcon = [MapPickerViewController systemImageNamedWithFallback:@"bookmark.fill" configuration:[UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIFontWeightSemibold]];
    [bmBtn setImage:bmIcon forState:UIControlStateNormal];
    bmBtn.tintColor = UIColor.systemYellowColor;
    bmBtn.accessibilityLabel = @"Save Bookmark";
    [bmBtn addTarget:self action:@selector(handleBookmarkSaveTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.previewCell.contentView addSubview:bmBtn];

    [NSLayoutConstraint activateConstraints:@[
        [previewBadge.leadingAnchor constraintEqualToAnchor:self.previewCell.contentView.leadingAnchor constant:16.0],
        [previewBadge.centerYAnchor constraintEqualToAnchor:self.previewCell.contentView.centerYAnchor],

        [previewTitle.leadingAnchor constraintEqualToAnchor:previewBadge.trailingAnchor constant:12.0],
        [previewTitle.topAnchor constraintEqualToAnchor:self.previewCell.contentView.topAnchor constant:10.0],

        [self.previewCoordLabel.leadingAnchor constraintEqualToAnchor:previewTitle.leadingAnchor],
        [self.previewCoordLabel.topAnchor constraintEqualToAnchor:previewTitle.bottomAnchor constant:3.0],
        [self.previewCoordLabel.bottomAnchor constraintEqualToAnchor:self.previewCell.contentView.bottomAnchor constant:-10.0],
        [self.previewCoordLabel.trailingAnchor constraintLessThanOrEqualToAnchor:bmBtn.leadingAnchor constant:-8.0],

        [bmBtn.trailingAnchor constraintEqualToAnchor:self.previewCell.contentView.trailingAnchor constant:-16.0],
        [bmBtn.centerYAnchor constraintEqualToAnchor:self.previewCell.contentView.centerYAnchor],
        [bmBtn.widthAnchor constraintEqualToConstant:36.0],
        [bmBtn.heightAnchor constraintEqualToConstant:36.0]
    ]];

    // 1: Coordinate Inputs (Latitude, Longitude, Altitude)
    self.latitudeCell = [self ls_createCoordinateCellWithBadgeSymbol:@"location.north.fill"
                                                          badgeColor:UIColor.systemBlueColor
                                                               title:@"Latitude"
                                                           textField:self.latitudeField];

    self.longitudeCell = [self ls_createCoordinateCellWithBadgeSymbol:@"globe.americas.fill"
                                                           badgeColor:UIColor.systemTealColor
                                                                title:@"Longitude"
                                                            textField:self.longitudeField];

    self.altitudeCell = [self ls_createCoordinateCellWithBadgeSymbol:@"mountain.2.fill"
                                                          badgeColor:UIColor.systemOrangeColor
                                                               title:@"Altitude"
                                                           textField:self.altitudeField];

    // 2: Heading Slider Cell
    self.headingCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.headingCell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.headingCell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *headingBadge = [MapPickerViewController iconBadgeWithSymbolName:@"safari.fill" backgroundColor:UIColor.systemIndigoColor];
    [self.headingCell.contentView addSubview:headingBadge];

    UILabel *headingLbl = [[UILabel alloc] init];
    headingLbl.translatesAutoresizingMaskIntoConstraints = NO;
    headingLbl.text = @"Heading";
    headingLbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    headingLbl.textColor = UIColor.labelColor;
    [self.headingCell.contentView addSubview:headingLbl];

    self.headingValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headingCell.contentView addSubview:self.headingValueLabel];

    self.headingSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.headingCell.contentView addSubview:self.headingSlider];

    [NSLayoutConstraint activateConstraints:@[
        [headingBadge.leadingAnchor constraintEqualToAnchor:self.headingCell.contentView.leadingAnchor constant:16.0],
        [headingBadge.topAnchor constraintEqualToAnchor:self.headingCell.contentView.topAnchor constant:12.0],

        [headingLbl.leadingAnchor constraintEqualToAnchor:headingBadge.trailingAnchor constant:12.0],
        [headingLbl.centerYAnchor constraintEqualToAnchor:headingBadge.centerYAnchor],

        [self.headingValueLabel.trailingAnchor constraintEqualToAnchor:self.headingCell.contentView.trailingAnchor constant:-16.0],
        [self.headingValueLabel.centerYAnchor constraintEqualToAnchor:headingBadge.centerYAnchor],
        [self.headingValueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:headingLbl.trailingAnchor constant:8.0],

        [self.headingSlider.topAnchor constraintEqualToAnchor:headingBadge.bottomAnchor constant:12.0],
        [self.headingSlider.leadingAnchor constraintEqualToAnchor:self.headingCell.contentView.leadingAnchor constant:16.0],
        [self.headingSlider.trailingAnchor constraintEqualToAnchor:self.headingCell.contentView.trailingAnchor constant:-16.0],
        [self.headingSlider.bottomAnchor constraintEqualToAnchor:self.headingCell.contentView.bottomAnchor constant:-14.0]
    ]];

    // 3: Options (Fluctuation, Radius, Keep Last, Show Real)
    self.fluctuationCell = [self ls_createToggleCellWithBadgeSymbol:@"waveform.path"
                                                         badgeColor:UIColor.systemPurpleColor
                                                              title:@"Location Fluctuation"
                                                           subtitle:@"Adds subtle randomized GPS drift"
                                                            control:self.fluctuationSwitch];

    self.fluctuationRadiusCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.fluctuationRadiusCell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.fluctuationRadiusCell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *radiusBadge = [MapPickerViewController iconBadgeWithSymbolName:@"circle.dashed" backgroundColor:[UIColor.systemPurpleColor colorWithAlphaComponent:0.75]];
    [self.fluctuationRadiusCell.contentView addSubview:radiusBadge];

    UILabel *radiusTitle = [[UILabel alloc] init];
    radiusTitle.translatesAutoresizingMaskIntoConstraints = NO;
    radiusTitle.text = @"Drift Radius";
    radiusTitle.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    radiusTitle.textColor = UIColor.labelColor;
    [self.fluctuationRadiusCell.contentView addSubview:radiusTitle];

    self.fluctuationRadiusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fluctuationRadiusCell.contentView addSubview:self.fluctuationRadiusLabel];

    self.fluctuationRadiusSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [self.fluctuationRadiusCell.contentView addSubview:self.fluctuationRadiusSlider];

    [NSLayoutConstraint activateConstraints:@[
        [radiusBadge.leadingAnchor constraintEqualToAnchor:self.fluctuationRadiusCell.contentView.leadingAnchor constant:16.0],
        [radiusBadge.topAnchor constraintEqualToAnchor:self.fluctuationRadiusCell.contentView.topAnchor constant:12.0],

        [radiusTitle.leadingAnchor constraintEqualToAnchor:radiusBadge.trailingAnchor constant:12.0],
        [radiusTitle.centerYAnchor constraintEqualToAnchor:radiusBadge.centerYAnchor],

        [self.fluctuationRadiusLabel.trailingAnchor constraintEqualToAnchor:self.fluctuationRadiusCell.contentView.trailingAnchor constant:-16.0],
        [self.fluctuationRadiusLabel.centerYAnchor constraintEqualToAnchor:radiusBadge.centerYAnchor],
        [self.fluctuationRadiusLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:radiusTitle.trailingAnchor constant:8.0],

        [self.fluctuationRadiusSlider.topAnchor constraintEqualToAnchor:radiusBadge.bottomAnchor constant:10.0],
        [self.fluctuationRadiusSlider.leadingAnchor constraintEqualToAnchor:self.fluctuationRadiusCell.contentView.leadingAnchor constant:16.0],
        [self.fluctuationRadiusSlider.trailingAnchor constraintEqualToAnchor:self.fluctuationRadiusCell.contentView.trailingAnchor constant:-16.0],
        [self.fluctuationRadiusSlider.bottomAnchor constraintEqualToAnchor:self.fluctuationRadiusCell.contentView.bottomAnchor constant:-12.0]
    ]];


    self.keepLastSpoofCell = [self ls_createToggleCellWithBadgeSymbol:@"clock.arrow.circlepath"
                                                           badgeColor:UIColor.systemGreenColor
                                                                title:@"Keep Last Location"
                                                             subtitle:@"Persist coordinate across app relaunches"
                                                              control:self.keepLastSpoofSwitch];

    self.showRealLocationCell = [self ls_createToggleCellWithBadgeSymbol:@"location.fill.viewfinder"
                                                              badgeColor:UIColor.systemBlueColor
                                                                   title:@"Show Real Location"
                                                                subtitle:@"Display native GPS blue dot on map"
                                                                 control:self.showRealLocationSwitch];

    // 4: Action Button Cells (Apply, Stop, Cancel)
    self.applyButtonCell = [self ls_createButtonCellWithView:self.applyButton];
    self.stopButtonCell = [self ls_createButtonCellWithView:self.stopButton];
    self.cancelButtonCell = [self ls_createButtonCellWithView:self.cancelButton];
}

- (UITableViewCell *)ls_createCoordinateCellWithBadgeSymbol:(NSString *)symbol
                                                 badgeColor:(UIColor *)color
                                                      title:(NSString *)title
                                                  textField:(UITextField *)textField {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *badge = [MapPickerViewController iconBadgeWithSymbolName:symbol backgroundColor:color];
    [cell.contentView addSubview:badge];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    lbl.textColor = UIColor.labelColor;
    [cell.contentView addSubview:lbl];

    [textField removeFromSuperview];
    textField.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:textField];

    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
        [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

        [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
        [lbl.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [lbl.widthAnchor constraintEqualToConstant:90.0],

        [textField.leadingAnchor constraintEqualToAnchor:lbl.trailingAnchor constant:8.0],
        [textField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
        [textField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [textField.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:6.0],
        [textField.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-6.0],
        [textField.heightAnchor constraintGreaterThanOrEqualToConstant:36.0]
    ]];
    return cell;
}

- (UITableViewCell *)ls_createToggleCellWithBadgeSymbol:(NSString *)symbol
                                             badgeColor:(UIColor *)color
                                                  title:(NSString *)title
                                               subtitle:(NSString *)subtitle
                                                control:(UIControl *)control {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *badge = [MapPickerViewController iconBadgeWithSymbolName:symbol backgroundColor:color];
    [cell.contentView addSubview:badge];

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = title;
    lbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    lbl.textColor = UIColor.labelColor;
    [cell.contentView addSubview:lbl];

    UILabel *sub = [[UILabel alloc] init];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.text = subtitle;
    sub.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    sub.textColor = UIColor.secondaryLabelColor;
    [cell.contentView addSubview:sub];

    [control removeFromSuperview];
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:control];

    [NSLayoutConstraint activateConstraints:@[
        [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
        [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

        [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
        [lbl.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],

        [sub.leadingAnchor constraintEqualToAnchor:lbl.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:2.0],
        [sub.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
        [sub.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-8.0],

        [control.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
        [control.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
    ]];
    return cell;
}

- (UITableViewCell *)ls_createButtonCellWithView:(UIView *)buttonView {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.backgroundColor = UIColor.clearColor;
    cell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.separatorInset = UIEdgeInsetsMake(0.0, 10000.0, 0.0, 0.0);

    [buttonView removeFromSuperview];
    [cell.contentView addSubview:buttonView];
    [NSLayoutConstraint activateConstraints:@[
        [buttonView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
        [buttonView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        [buttonView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
        [buttonView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0],
        [buttonView.heightAnchor constraintEqualToConstant:48.0]
    ]];
    return cell;
}

#pragma mark - Map

- (void)configureMapIfNeeded {
    if (self.mapConfigured) {
        return;
    }

    self.mapConfigured = YES;
    [self.mapSpinner startAnimating];

    self.pinAnnotation = [[MKPointAnnotation alloc] init];
    self.pinAnnotation.title = @"Spoofed location";
    self.pinAnnotation.subtitle = @"Drag to adjust";

    if (self.hasSelectedCoordinate && CLLocationCoordinate2DIsValid(self.selectedCoordinate) && (self.selectedCoordinate.latitude != 0 || self.selectedCoordinate.longitude != 0)) {
        self.pinAnnotation.coordinate = self.selectedCoordinate;
        [self.mapView addAnnotation:self.pinAnnotation];
        MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.selectedCoordinate, 1500.0, 1500.0);
        [self.mapView setRegion:region animated:NO];
    } else {
        CLLocation *userLoc = self.mapView.userLocation.location;
        if (userLoc && CLLocationCoordinate2DIsValid(userLoc.coordinate) && (userLoc.coordinate.latitude != 0 || userLoc.coordinate.longitude != 0)) {
            self.selectedCoordinate = userLoc.coordinate;
            self.hasSelectedCoordinate = YES;
            self.pinAnnotation.coordinate = userLoc.coordinate;
            [self.mapView addAnnotation:self.pinAnnotation];
            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(userLoc.coordinate, 1500.0, 1500.0);
            [self.mapView setRegion:region animated:NO];
            [self syncFieldsFromCoordinate];
        }
    }
    [self updateSearchCompleterRegion];
}

- (void)mapView:(MKMapView *)mapView didUpdateUserLocation:(MKUserLocation *)userLocation {
    if (!self.hasSelectedCoordinate && userLocation.location) {
        CLLocationCoordinate2D coord = userLocation.location.coordinate;
        if (CLLocationCoordinate2DIsValid(coord) && (coord.latitude != 0 || coord.longitude != 0)) {
            self.selectedCoordinate = coord;
            self.hasSelectedCoordinate = YES;
            [PersistenceManager shared].lastRealCoordinate = coord;
            [PersistenceManager shared].hasRealCoordinate = YES;
            [self syncFieldsFromCoordinate];
            [self updatePinOnMapAnimated:YES];
            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord, 1500.0, 1500.0);
            [self.mapView setRegion:region animated:YES];
        }
    }
}


- (void)syncFieldsFromCoordinate {
    self.suppressFieldSync = YES;
    self.latitudeField.text = [NSString stringWithFormat:@"%.6f", self.selectedCoordinate.latitude];
    self.longitudeField.text = [NSString stringWithFormat:@"%.6f", self.selectedCoordinate.longitude];
    self.suppressFieldSync = NO;
    [self updateCoordinateLabel];
    [self updatePinOnMapAnimated:NO];
}

- (void)updateCoordinateLabel {
    self.previewCoordLabel.text = [NSString stringWithFormat:@"%@%.6f, %@%.6f",
                                   self.selectedCoordinate.latitude >= 0 ? @"N " : @"S ",
                                   fabs(self.selectedCoordinate.latitude),
                                   self.selectedCoordinate.longitude >= 0 ? @"E " : @"W ",
                                   fabs(self.selectedCoordinate.longitude)];
}

- (void)movePinToCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated {
    self.selectedCoordinate = coordinate;
    self.hasSelectedCoordinate = YES;
    self.suppressFieldSync = YES;
    if (!self.latitudeField.isFirstResponder) {
        self.latitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.latitude];
    }
    if (!self.longitudeField.isFirstResponder) {
        self.longitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.longitude];
    }
    self.suppressFieldSync = NO;
    [self updateCoordinateLabel];
    [self updatePinOnMapAnimated:animated];
}

- (void)updatePinOnMapAnimated:(BOOL)animated {
    if (!self.pinAnnotation) {
        return;
    }

    self.pinAnnotation.coordinate = self.selectedCoordinate;

    if (!MKMapRectContainsPoint(self.mapView.visibleMapRect, MKMapPointForCoordinate(self.selectedCoordinate))) {
        MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.selectedCoordinate, 1500.0, 1500.0);
        [self.mapView setRegion:region animated:animated];
    }
}

#pragma mark - Validation & Input

- (nullable NSNumber *)ls_parsedCoordinateComponentFromText:(NSString *)text {
    if (!text || text.length == 0) {
        return nil;
    }
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }

    NSString *normalized = [trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."];

    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });

    NSNumber *num = [formatter numberFromString:normalized];
    if (num) {
        return num;
    }

    // Resilient scanner for strings containing units (e.g. "50 m", "30 km/h")
    NSScanner *scanner = [NSScanner scannerWithString:normalized];
    scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    double val = 0.0;
    if ([scanner scanDouble:&val]) {
        return @(val);
    }

    return nil;
}

- (BOOL)applyFieldsToCoordinate {
    if (self.suppressFieldSync) {
        return YES;
    }

    NSNumber *latitudeNumber = [self ls_parsedCoordinateComponentFromText:self.latitudeField.text];
    NSNumber *longitudeNumber = [self ls_parsedCoordinateComponentFromText:self.longitudeField.text];
    if (!latitudeNumber || !longitudeNumber) {
        return NO;
    }

    double latitude = latitudeNumber.doubleValue;
    double longitude = longitudeNumber.doubleValue;
    if (latitude < -90.0 || latitude > 90.0 || longitude < -180.0 || longitude > 180.0) {
        return NO;
    }

    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(latitude, longitude);
    self.selectedCoordinate = coord;
    self.hasSelectedCoordinate = YES;
    [self updateCoordinateLabel];
    [self updatePinOnMapAnimated:YES];
    return YES;
}

- (void)showInvalidCoordinateFeedback {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];

    UITableViewCell *latCell = self.latitudeCell;
    if (latCell) {
        CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
        shake.values = @[@0, @-8, @8, @-6, @6, @0];
        shake.duration = 0.35;
        [latCell.layer addAnimation:shake forKey:@"shake"];
    }
}

- (void)playApplyHaptic {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
}

- (void)playSimulationStopHaptic {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];
}

- (void)playRouteSuccessHaptic {
    UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
    [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
}

- (void)playRouteFailureHaptic {
    UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
    [feedback notificationOccurred:UINotificationFeedbackTypeError];
}

- (void)playBookmarkSavedHaptic {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
}

- (BOOL)applyAltitudeField {
    NSNumber *altitudeNumber = [self ls_parsedCoordinateComponentFromText:self.altitudeField.text];
    if (!altitudeNumber) {
        return NO;
    }
    double altitude = altitudeNumber.doubleValue;
    if (altitude < -500.0 || altitude > 10000.0) {
        return NO;
    }
    [PersistenceManager shared].altitude = altitude;
    return YES;
}

- (void)handleHeadingSliderChanged:(UISlider *)sender {
    (void)sender;
    NSInteger heading = (NSInteger)lroundf(self.headingSlider.value);
    [PersistenceManager shared].heading = (CLLocationDirection)heading;
    [self updateHeadingLabel];
}

- (void)updateHeadingLabel {
    NSInteger heading = (NSInteger)lroundf(self.headingSlider.value);
    NSArray<NSString *> *directions = @[@"N", @"NE", @"E", @"SE", @"S", @"SW", @"W", @"NW"];
    NSInteger index = (NSInteger)(((double)heading + 22.5) / 45.0) % 8;
    NSString *cardinal = directions[index];

    self.headingValueLabel.text = [NSString stringWithFormat:@"%03ld° %@", (long)heading, cardinal];

    CGFloat hue = (CGFloat)heading / 360.0;
    self.headingSlider.tintColor = [UIColor colorWithHue:hue saturation:0.65 brightness:0.85 alpha:1.0];
}

- (void)handleFluctuationToggle {
    self.fluctuationSwitch.userInteractionEnabled = NO;
    PersistenceManager *store = [PersistenceManager shared];
    store.fluctuationEnabled = self.fluctuationSwitch.isOn;

    NSIndexPath *radiusPath = [NSIndexPath indexPathForRow:1 inSection:4];
    __weak typeof(self) weakSelf = self;
    [self.tableView performBatchUpdates:^{
        if (weakSelf.fluctuationSwitch.isOn) {
            [weakSelf.tableView insertRowsAtIndexPaths:@[radiusPath] withRowAnimation:UITableViewRowAnimationFade];
        } else {
            [weakSelf.tableView deleteRowsAtIndexPaths:@[radiusPath] withRowAnimation:UITableViewRowAnimationFade];
        }
    } completion:^(BOOL finished) {
        (void)finished;
        weakSelf.fluctuationSwitch.userInteractionEnabled = YES;
    }];
}

- (void)handleFluctuationRadiusSliderChanged:(UISlider *)sender {
    double radius = round(sender.value);
    self.fluctuationRadiusLabel.text = [NSString stringWithFormat:@"%.0f m", radius];
    [PersistenceManager shared].fluctuationRadius = radius;
}

- (void)handleCheckForUpdatesTapped {
    [LSUpdateChecker checkForUpdatesManuallyFromViewController:self];
}

- (void)updateHeroStatusCell {
    if (!self.heroStatusCell) return;
    PersistenceManager *store = [PersistenceManager shared];
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    BOOL active = [store isSpoofingEnabled] || simulator.isSimulating;

    self.heroStatusSwitch.on = active;
    if (active) {
        self.heroStatusDot.backgroundColor = UIColor.systemGreenColor;
        self.heroStatusTitleLabel.text = simulator.isSimulating ? @"Simulation Active" : @"Spoofing Active";
        self.heroStatusSubtitleLabel.text = @"Apps receive your chosen GPS coordinates";
    } else {
        self.heroStatusDot.backgroundColor = UIColor.systemOrangeColor;
        self.heroStatusTitleLabel.text = @"Spoofing Inactive";
        self.heroStatusSubtitleLabel.text = @"Using device native GPS · Toggle to activate";
    }
}

- (void)handleHeroStatusSwitchToggled:(UISwitch *)sender {
    PersistenceManager *store = [PersistenceManager shared];
    if (sender.isOn) {
        if (![self applyFieldsToCoordinate] || ![self applyAltitudeField]) {
            [self showInvalidCoordinateFeedback];
            sender.on = NO;
            return;
        }
        if (![store setSpoofCoordinate:self.selectedCoordinate enabled:YES]) {
            [self showInvalidCoordinateFeedback];
            sender.on = NO;
            return;
        }
        [store recordRecentCoordinate:self.selectedCoordinate name:nil];
        [self playApplyHaptic];
        [self updateHeroStatusCell];
        [self refreshStatusPill];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:5] withRowAnimation:UITableViewRowAnimationNone];
    } else {
        [[LSRouteSimulator shared] stop];
        [store clearSpoof];
        store.simulationWasActive = NO;
        [self playSimulationStopHaptic];
        [self updateHeroStatusCell];
        [self refreshStatusPill];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:5] withRowAnimation:UITableViewRowAnimationNone];
    }
}


- (void)handleKeepLastSpoofToggle {
    [PersistenceManager shared].keepLastSpoof = self.keepLastSpoofSwitch.isOn;
}

- (void)handleShowRealLocationToggle {
    [PersistenceManager shared].showRealLocation = self.showRealLocationSwitch.isOn;
    [self refreshStatusPill];
}

#pragma mark - Search Suggestions & Autocomplete

- (void)configureSearchCompleter {
    self.searchCompletions = @[];
    self.searchCompleter = [[MKLocalSearchCompleter alloc] init];
    self.searchCompleter.delegate = self;
    self.searchCompleter.resultTypes = MKLocalSearchCompleterResultTypeAddress | MKLocalSearchCompleterResultTypeQuery;
}

- (void)updateSearchCompleterRegion {
    if (self.mapConfigured) {
        self.searchCompleter.region = self.mapView.region;
    }
}

- (void)updateSearchSuggestionsVisibility {
    NSInteger count = self.searchCompletions.count;
    BOOL shouldShow = count > 0 && self.searchBar.isFirstResponder;

    if (shouldShow) {
        NSInteger visibleRows = MIN(count, 4);
        CGFloat targetHeight = MIN(visibleRows * kLSSuggestionRowHeight, kLSSuggestionMaxHeight);
        self.suggestionsHeightConstraint.constant = targetHeight;
        self.suggestionsPanel.hidden = NO;

        if (!self.searchSuggestionsVisible) {
            self.searchSuggestionsVisible = YES;
            self.suggestionsPanel.alpha = 0.0;
            [UIView animateWithDuration:0.18 animations:^{
                self.suggestionsPanel.alpha = 1.0;
                [self.tableHeaderContainer layoutIfNeeded];
            }];
        } else {
            [self.tableHeaderContainer layoutIfNeeded];
        }
    } else {
        [self hideSearchSuggestions];
    }
}

- (void)hideSearchSuggestions {
    self.searchSuggestionsVisible = NO;
    self.suggestionsHeightConstraint.constant = 0.0;

    if (!self.suggestionsPanel.hidden) {
        [UIView animateWithDuration:0.15 animations:^{
            self.suggestionsPanel.alpha = 0.0;
            [self.tableHeaderContainer layoutIfNeeded];
        } completion:^(__unused BOOL finished) {
            self.suggestionsPanel.hidden = YES;
        }];
    }
}

- (void)updateSearchQueryFragment:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length > 256) return;
    if (trimmed.length == 0) {
        self.searchCompletions = @[];
        self.searchCompleter.queryFragment = @"";
        [self.suggestionsTableView reloadData];
        [self hideSearchSuggestions];
        [self.searchSpinner stopAnimating];
        return;
    }

    [self updateSearchCompleterRegion];
    self.searchCompleter.queryFragment = trimmed;
    [self.searchSpinner startAnimating];
}

- (void)resolveSearchCompletion:(MKLocalSearchCompletion *)completion {
    if (!completion) return;

    [self hideSearchSuggestions];
    [self.searchBar resignFirstResponder];
    self.searchBar.text = completion.title;
    [self.searchSpinner startAnimating];

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] initWithCompletion:completion];
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.searchSpinner stopAnimating];
            if (error || response.mapItems.count == 0) return;
            MKMapItem *item = response.mapItems.firstObject;
            [strongSelf movePinToCoordinate:item.placemark.coordinate animated:YES];
        });
    }];
}

- (void)resolveSearchQuery:(NSString *)query {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return;

    [self hideSearchSuggestions];
    [self.searchBar resignFirstResponder];
    [self.searchSpinner startAnimating];

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = trimmed;
    [self updateSearchCompleterRegion];
    request.region = self.searchCompleter.region;

    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.searchSpinner stopAnimating];
            if (error || response.mapItems.count == 0) return;
            MKMapItem *item = response.mapItems.firstObject;
            [strongSelf movePinToCoordinate:item.placemark.coordinate animated:YES];
        });
    }];
}

#pragma mark - MKLocalSearchCompleterDelegate

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer {
    (void)completer;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.searchCompletions = completer.results ?: @[];
        [self.searchSpinner stopAnimating];
        [self.suggestionsTableView reloadData];
        [self updateSearchSuggestionsVisibility];
    });
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error {
    (void)completer;
    (void)error;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.searchSpinner stopAnimating];
        [self hideSearchSuggestions];
    });
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
    [self.searchSpinner stopAnimating];
    [self updateSearchSuggestionsVisibility];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.searchBar.isFirstResponder) {
            [self hideSearchSuggestions];
        }
    });
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    searchBar.showsCancelButton = NO;
    [self hideSearchSuggestions];
    [self.searchSpinner stopAnimating];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    (void)searchBar;
    [self updateSearchQueryFragment:searchText];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    if (self.searchCompletions.count > 0) {
        [self resolveSearchCompletion:self.searchCompletions.firstObject];
        return;
    }
    [self resolveSearchQuery:searchBar.text];
}

#pragma mark - Keyboard

- (void)configureKeyboardToolbar {
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
    UIBarButtonItem *plusMinus = [[UIBarButtonItem alloc] initWithTitle:@"+/-" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSignForActiveField)];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    toolbar.items = @[plusMinus, flex, done];

    self.latitudeField.inputAccessoryView = toolbar;
    self.longitudeField.inputAccessoryView = toolbar;
    self.altitudeField.inputAccessoryView = toolbar;
    self.customSpeedField.inputAccessoryView = toolbar;
}

- (void)toggleSignForActiveField {
    UITextField *target = nil;
    if (self.latitudeField.isFirstResponder) target = self.latitudeField;
    else if (self.longitudeField.isFirstResponder) target = self.longitudeField;
    if (!target) return;

    NSString *text = target.text ?: @"";
    if ([text hasPrefix:@"-"]) {
        target.text = [text substringFromIndex:1];
    } else {
        target.text = [@"-" stringByAppendingString:text];
    }
    [self textFieldDidChange:target];
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
    [self hideSearchSuggestions];
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    if (textField == self.altitudeField) {
        NSString *raw = [textField.text stringByReplacingOccurrencesOfString:@" m" withString:@""];
        textField.text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    } else if (textField == self.customSpeedField) {
        NSString *raw = [textField.text stringByReplacingOccurrencesOfString:@" km/h" withString:@""];
        textField.text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    }
}

- (void)textFieldDidChange:(UITextField *)textField {
    if (textField == self.customSpeedField) {
        NSNumber *parsed = [self ls_parsedCoordinateComponentFromText:textField.text];
        BOOL valid = parsed && parsed.doubleValue >= 1.0 && parsed.doubleValue <= 500.0;
        textField.textColor = valid ? UIColor.labelColor : UIColor.systemRedColor;
        return;
    }

    if (textField == self.latitudeField || textField == self.longitudeField) {
        [self applyFieldsToCoordinate];
    }
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == self.latitudeField || textField == self.longitudeField) {
        if (![self applyFieldsToCoordinate]) {
            [self showInvalidCoordinateFeedback];
            [self syncFieldsFromCoordinate];
        } else {
            [self syncFieldsFromCoordinate];
        }
    } else if (textField == self.altitudeField) {
        NSNumber *alt = [self ls_parsedCoordinateComponentFromText:textField.text];
        if (alt && alt.doubleValue >= -500.0 && alt.doubleValue <= 10000.0) {
            [PersistenceManager shared].altitude = alt.doubleValue;
            textField.text = [NSString stringWithFormat:@"%.0f m", alt.doubleValue];
        } else {
            textField.text = [NSString stringWithFormat:@"%.0f m", [PersistenceManager shared].altitude];
        }
    } else if (textField == self.customSpeedField) {

        NSNumber *spd = [self ls_parsedCoordinateComponentFromText:textField.text];
        double val = (spd && spd.doubleValue >= 1.0 && spd.doubleValue <= 500.0) ? spd.doubleValue : 30.0;
        [LSRouteSimulator shared].customSpeedKmh = val;
        textField.text = [NSString stringWithFormat:@"%.0f km/h", val];
        textField.textColor = UIColor.labelColor;
    }
}

- (void)ls_keyboardWillShow:(NSNotification *)note {
    CGRect kbFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect viewKbFrame = [self.view convertRect:kbFrame fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.tableView.frame) - viewKbFrame.origin.y;
    CGFloat bottomInset = MAX(overlap, 0.0);

    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = (UIViewAnimationOptions)([note.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16);

    [UIView animateWithDuration:duration delay:0 options:curve animations:^{
        UIEdgeInsets insets = self.tableView.contentInset;
        insets.bottom = bottomInset;
        self.tableView.contentInset = insets;
        self.tableView.scrollIndicatorInsets = insets;
    } completion:nil];
}

- (void)ls_keyboardWillHide:(NSNotification *)note {
    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationOptions curve = (UIViewAnimationOptions)([note.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue] << 16);

    [UIView animateWithDuration:duration delay:0 options:curve animations:^{
        UIEdgeInsets insets = self.tableView.contentInset;
        insets.bottom = 0.0;
        self.tableView.contentInset = insets;
        self.tableView.scrollIndicatorInsets = insets;
    } completion:nil];
}

#pragma mark - Status Pill

- (void)refreshStatusPill {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (simulator.isSimulating) {
        double kmh = [LSRouteSimulator speedMetersPerSecondForMode:simulator.transportMode customSpeedKmh:simulator.customSpeedKmh] * 3.6;
        self.statusLabel.text = [NSString stringWithFormat:@"Simulating · %.1f km/h", kmh];
        self.statusDot.backgroundColor = UIColor.systemGreenColor;
    } else {
        BOOL active = [[PersistenceManager shared] isSpoofingEnabled];
        self.statusLabel.text = active ? @"Spoofing active" : @"Spoofing inactive";
        self.statusDot.backgroundColor = active ? UIColor.systemGreenColor : UIColor.systemOrangeColor;
    }

    BOOL active = [[PersistenceManager shared] isSpoofingEnabled] || simulator.isSimulating;
    self.pillStopLabel.hidden = !active;
    self.statusPill.backgroundColor = active ? [UIColor.systemRedColor colorWithAlphaComponent:0.12] : [UIColor.tertiarySystemFillColor colorWithAlphaComponent:0.9];

    BOOL showReal = [[PersistenceManager shared] isSpoofingEnabled] && [PersistenceManager shared].showRealLocation;
    self.mapView.showsUserLocation = ![[PersistenceManager shared] isSpoofingEnabled] || showReal;
    [self updateHeroStatusCell];
}

- (void)handleStatusPillTapped {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (simulator.isSimulating || [[PersistenceManager shared] isSpoofingEnabled]) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Stop Spoofing?"
                                                                       message:nil
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        __weak typeof(self) weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:@"Stop" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf handleStopSpoofing];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:sheet animated:YES completion:nil];
    }
}

#pragma mark - Actions

- (void)handleApply {
    [self dismissKeyboard];
    if ([self.searchSpinner isAnimating]) {
        return;
    }
    if (![self applyFieldsToCoordinate] || ![self applyAltitudeField]) {
        [self showInvalidCoordinateFeedback];
        return;
    }

    PersistenceManager *store = [PersistenceManager shared];
    if (![store setSpoofCoordinate:self.selectedCoordinate enabled:YES]) {
        [self showInvalidCoordinateFeedback];
        return;
    }

    NSString *name = (self.searchBar.text.length > 0) ? self.searchBar.text : nil;
    [store recordRecentCoordinate:self.selectedCoordinate name:name];
    [self playApplyHaptic];
    [self updateHeroStatusCell];
    [self refreshStatusPill];
    LSSetHooksBypassed(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleCancel {
    LSSetHooksBypassed(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleStopSpoofing {
    [[LSRouteSimulator shared] stop];
    [[PersistenceManager shared] clearSpoof];
    [PersistenceManager shared].simulationWasActive = NO;
    [self playSimulationStopHaptic];
    [self updateHeroStatusCell];
    [self refreshStatusPill];
    LSSetHooksBypassed(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}


- (void)handleMapTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;

    [self hideSearchSuggestions];
    [self.searchBar resignFirstResponder];

    CGPoint point = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];

    if (self.coordinateMode == LSMapPickerCoordinateModeRoute) {
        [self ls_handleRouteMapTap:coordinate];
        return;
    }

    [self movePinToCoordinate:coordinate animated:YES];
}

- (void)handleMapLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    [self hideSearchSuggestions];
    [self.searchBar resignFirstResponder];

    CGPoint point = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];

    if (self.coordinateMode == LSMapPickerCoordinateModeStatic) {
        [self ls_presentStaticMapActionSheetAtCoordinate:coordinate];
        return;
    }

    [self ls_handleRouteMapTap:coordinate];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == self.mapLongPressGesture) {
        if ([touch.view isKindOfClass:[MKAnnotationView class]] ||
            [touch.view.superview isKindOfClass:[MKAnnotationView class]]) {
            return NO;
        }
    }
    return YES;
}

- (void)mapViewDidFinishLoadingMap:(MKMapView *)mapView {
    (void)mapView;
    [self.mapSpinner stopAnimating];
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    (void)mapView;
    return [self ls_rendererForMapOverlay:overlay];
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    MKAnnotationView *routeView = [self ls_viewForRouteAnnotation:annotation];
    if (routeView) {
        return routeView;
    }

    if (annotation != self.pinAnnotation) {
        return nil;
    }

    static NSString * const reuseIdentifier = @"LSSpoofPin";
    MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:reuseIdentifier];
    if (!view) {
        view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
        view.canShowCallout = YES;
        view.draggable = YES;
        view.markerTintColor = UIColor.systemRedColor;
        view.glyphImage = [MapPickerViewController systemImageNamedWithFallback:@"mappin.and.ellipse" configuration:nil];
        view.displayPriority = MKFeatureDisplayPriorityRequired;
    } else {
        view.annotation = annotation;
    }
    return view;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view didChangeDragState:(MKAnnotationViewDragState)newState fromOldState:(MKAnnotationViewDragState)oldState {
    (void)mapView;
    (void)oldState;
    if (newState == MKAnnotationViewDragStateEnding || newState == MKAnnotationViewDragStateCanceling) {
        [view setDragState:MKAnnotationViewDragStateNone animated:YES];
        if (view.annotation == self.pinAnnotation) {
            [self movePinToCoordinate:view.annotation.coordinate animated:NO];
        } else {
            [self ls_routeAnnotationDragEnded:view];
        }
    }
}

#pragma mark - UITableViewDataSource & UITableViewDelegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (tableView == self.suggestionsTableView) {
        return 1;
    }

    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        return [self ls_bookmarksNumberOfSections];
    }

    if (self.coordinateMode == LSMapPickerCoordinateModeRoute) {
        return [self ls_routeNumberOfSections];
    }

    // Static mode: 6 sections (Hero status, Selected location, Coordinates, Heading, Options, Actions)
    return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.suggestionsTableView) {
        return self.searchCompletions.count;
    }

    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        return [self ls_bookmarksNumberOfRowsInSection:section];
    }

    if (self.coordinateMode == LSMapPickerCoordinateModeRoute) {
        return [self ls_routeNumberOfRowsInSection:section];
    }

    // Static mode row counts
    switch (section) {
        case 0: return 1; // Hero Status Card (Big Active / Inactive indicator & switch)
        case 1: return 1; // Preview & Bookmark
        case 2: return 3; // Latitude, Longitude, Altitude
        case 3: return 1; // Heading slider
        case 4: return self.fluctuationSwitch.isOn ? 4 : 3; // Fluctuation, (Radius Slider), Keep Last, Show Real
        case 5: return [[PersistenceManager shared] isSpoofingEnabled] ? 3 : 2; // Apply, (Stop), Cancel
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (tableView == self.suggestionsTableView) {
        return nil;
    }

    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        return [self ls_bookmarksTitleForHeaderInSection:section];
    }

    if (self.coordinateMode == LSMapPickerCoordinateModeRoute) {
        return [self ls_routeTitleForHeaderInSection:section];
    }

    switch (section) {
        case 0: return @"Status";
        case 1: return @"Selected Location";
        case 2: return @"Coordinates";
        case 3: return @"Bearing & Direction";
        case 4: return @"Spoofing Options";
        default: return nil;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (tableView == self.suggestionsTableView) {
        return nil;
    }

    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        return [self ls_bookmarksHeaderForSection:section];
    }

    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Search suggestions
    if (tableView == self.suggestionsTableView) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LSSearchSuggestionCell" forIndexPath:indexPath];
        if (indexPath.row < (NSInteger)self.searchCompletions.count) {
            MKLocalSearchCompletion *completion = self.searchCompletions[indexPath.row];
            UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
            content.text = completion.title;
            content.secondaryText = completion.subtitle;
            content.textProperties.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
            content.secondaryTextProperties.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
            content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
            content.image = [MapPickerViewController systemImageNamedWithFallback:@"mappin.circle.fill" configuration:nil];
            content.imageProperties.tintColor = UIColor.systemBlueColor;
            cell.contentConfiguration = content;
        }
        cell.backgroundColor = UIColor.clearColor;
        return cell;
    }

    // Bookmarks tab
    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        return [self ls_bookmarksCellForRowAtIndexPath:indexPath];
    }

    // Route mode
    if (self.coordinateMode == LSMapPickerCoordinateModeRoute) {
        return [self ls_routeCellForRowAtIndexPath:indexPath];
    }

    // Static mode: Return retained static cells
    switch (indexPath.section) {
        case 0:
            return self.heroStatusCell;

        case 1:
            return self.previewCell;

        case 2:
            if (indexPath.row == 0) return self.latitudeCell;
            if (indexPath.row == 1) return self.longitudeCell;
            return self.altitudeCell;

        case 3:
            return self.headingCell;

        case 4: {
            if (indexPath.row == 0) return self.fluctuationCell;
            if (self.fluctuationSwitch.isOn) {
                if (indexPath.row == 1) return self.fluctuationRadiusCell;
                if (indexPath.row == 2) return self.keepLastSpoofCell;
                return self.showRealLocationCell;
            } else {
                if (indexPath.row == 1) return self.keepLastSpoofCell;
                return self.showRealLocationCell;
            }
        }

        case 5: {
            BOOL isSpoofingActive = [[PersistenceManager shared] isSpoofingEnabled];
            if (indexPath.row == 0) return self.applyButtonCell;
            if (indexPath.row == 1 && isSpoofingActive) return self.stopButtonCell;
            return self.cancelButtonCell;
        }

        default:
            return [[UITableViewCell alloc] init];
    }
}


- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (tableView == self.suggestionsTableView) {
        if (indexPath.row < (NSInteger)self.searchCompletions.count) {
            [self resolveSearchCompletion:self.searchCompletions[indexPath.row]];
        }
        return;
    }

    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        [self ls_bookmarksDidSelectRowAtIndexPath:indexPath];
        return;
    }

    if (self.coordinateMode == LSMapPickerCoordinateModeRoute) {
        [self ls_routeDidSelectRowAtIndexPath:indexPath];
        return;
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        return [self ls_bookmarksCanEditRowAtIndexPath:indexPath];
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.panelTab == LSMapPickerPanelTabBookmarks && editingStyle == UITableViewCellEditingStyleDelete) {
        [self ls_bookmarksCommitDeleteAtIndexPath:indexPath];
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        return [self ls_bookmarksCanMoveRowAtIndexPath:indexPath];
    }
    return NO;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (self.panelTab == LSMapPickerPanelTabBookmarks) {
        [self ls_bookmarksMoveFromIndexPath:sourceIndexPath toIndexPath:destinationIndexPath];
    }
}

@end
