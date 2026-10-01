#import "MapPickerViewController.h"
#import "MapPickerViewController+Private.h"
#import "LocationSpoofer.h"
#import "OverlayWindow.h"
#import "PersistenceManager.h"
#import "RouteSimulator.h"

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
    self.selectedCoordinate = CLLocationCoordinate2DMake(37.7749, -122.4194);
    self.hasSelectedCoordinate = NO;

    PersistenceManager *store = [PersistenceManager shared];
    if ([store isSpoofingEnabled] || [store hasStoredCoordinate]) {
        self.selectedCoordinate = [store spoofCoordinate];
        self.hasSelectedCoordinate = YES;
    }
    self.panelTab = LSMapPickerPanelTabMap;
    self.coordinateMode = LSMapPickerCoordinateModeStatic;

    [self buildInterface];
    [self buildRouteControls];
    [self buildBookmarksPanel];
    [self configureKeyboardToolbar];
    [self configureSearchCompleter];
    [self restoreSimulationUIIfNeeded];
    [self refreshStatusPill];
    [self syncFieldsFromCoordinate];

    self.altitudeField.text = [NSString stringWithFormat:@"%.0f", store.altitude];
    self.headingSlider.value = (float)store.heading;
    [self updateHeadingLabel];
    [self updatePanelTabVisibility];

    self.fluctuationSwitch.on = store.fluctuationEnabled;
    self.fluctuationRadiusField.text = [NSString stringWithFormat:@"%.0f", store.fluctuationRadius];
    self.keepLastSpoofSwitch.on = store.keepLastSpoof;
    self.showRealLocationSwitch.on = store.showRealLocation;

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ls_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(ls_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
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
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [LSOverlayManager restoreMapPickerSessionState];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [LSOverlayManager restoreMapPickerSessionState];
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
    UIImage *closeImage = [UIImage systemImageNamed:@"xmark.circle.fill" withConfiguration:closeConfig];
    [self.closeButton setImage:closeImage forState:UIControlStateNormal];
    self.closeButton.tintColor = UIColor.tertiaryLabelColor;
    self.closeButton.accessibilityLabel = @"Close";
    [self.closeButton addTarget:self action:@selector(handleCancel) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.closeButton];

    // Status pill
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
    [self.statusPill addSubview:self.statusDot];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    [self.statusPill addSubview:self.statusLabel];

    self.pillStopLabel = [[UILabel alloc] init];
    self.pillStopLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.pillStopLabel.text = @"Stop";
    self.pillStopLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold];
    self.pillStopLabel.textColor = UIColor.systemRedColor;
    self.pillStopLabel.hidden = YES;
    [self.statusPill addSubview:self.pillStopLabel];

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

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapTap:)];
    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleMapLongPress:)];
    longPressGesture.minimumPressDuration = 0.25;
    [tapGesture requireGestureRecognizerToFail:longPressGesture];
    [self.mapView addGestureRecognizer:tapGesture];
    [self.mapView addGestureRecognizer:longPressGesture];

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

    // Floating Search Suggestions Overlay (above mapContainer)
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
    self.suggestionsTableView.sectionHeaderHeight = 0.0;
    self.suggestionsTableView.sectionFooterHeight = 0.0;
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

        [self.statusDot.leadingAnchor constraintEqualToAnchor:self.statusPill.leadingAnchor constant:10.0],
        [self.statusDot.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],
        [self.statusDot.widthAnchor constraintEqualToConstant:8.0],
        [self.statusDot.heightAnchor constraintEqualToConstant:8.0],

        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusDot.trailingAnchor constant:8.0],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.statusPill.topAnchor constant:6.0],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.statusPill.bottomAnchor constant:-6.0],

        [self.pillStopLabel.leadingAnchor constraintEqualToAnchor:self.statusLabel.trailingAnchor constant:6.0],
        [self.pillStopLabel.centerYAnchor constraintEqualToAnchor:self.statusPill.centerYAnchor],
        [self.pillStopLabel.trailingAnchor constraintEqualToAnchor:self.statusPill.trailingAnchor constant:-12.0],

        [self.searchBar.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:10.0],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:tableHeader.leadingAnchor constant:10.0],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:tableHeader.trailingAnchor constant:-10.0],
        [self.searchBar.heightAnchor constraintEqualToConstant:48.0],

        [self.searchSpinner.centerYAnchor constraintEqualToAnchor:self.searchBar.centerYAnchor],
        [self.searchSpinner.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor constant:-16.0],

        [self.mapContainer.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:6.0],
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
        [self.coordinateModeSegment.heightAnchor constraintEqualToConstant:32.0],
        [self.coordinateModeSegment.bottomAnchor constraintEqualToAnchor:tableHeader.bottomAnchor constant:-8.0]
    ]];

    self.suggestionsHeightConstraint = [self.suggestionsPanel.heightAnchor constraintEqualToConstant:0.0];
    self.suggestionsHeightConstraint.active = YES;

    // Size header for table view
    [tableHeader layoutIfNeeded];
    CGFloat headerHeight = [tableHeader systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
    tableHeader.frame = CGRectMake(0, 0, self.view.bounds.size.width, headerHeight);
    self.tableView.tableHeaderView = tableHeader;
}

- (void)buildControls {
    // Latitude text field
    self.latitudeField = [self ls_createInputTextFieldWithPlaceholder:@"37.774900"];
    [self.latitudeField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    // Longitude text field
    self.longitudeField = [self ls_createInputTextFieldWithPlaceholder:@"-122.419400"];
    [self.longitudeField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    // Altitude text field
    self.altitudeField = [self ls_createInputTextFieldWithPlaceholder:@"0 m"];
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

    self.fluctuationRadiusField = [self ls_createInputTextFieldWithPlaceholder:@"50 m"];
    self.fluctuationRadiusField.keyboardType = UIKeyboardTypeNumberPad;
    [self.fluctuationRadiusField addTarget:self action:@selector(handleFluctuationRadiusChanged) forControlEvents:UIControlEventEditingDidEnd];

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
    UIImage *checkIcon = [UIImage systemImageNamed:@"checkmark.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIFontWeightBold]];
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
    UIImage *stopIcon = [UIImage systemImageNamed:@"stop.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17.0 weight:UIFontWeightBold]];
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

#pragma mark - Icon Badge Factory

+ (UIView *)iconBadgeWithSymbolName:(NSString *)symbolName backgroundColor:(UIColor *)bgColor {
    UIView *badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 30.0, 30.0)];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    badge.backgroundColor = bgColor;
    badge.layer.cornerRadius = 7.0;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.clipsToBounds = YES;

    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14.0 weight:UIFontWeightSemibold];
    UIImage *image = [UIImage systemImageNamed:symbolName withConfiguration:config];
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
    self.pinAnnotation.coordinate = self.selectedCoordinate;
    [self.mapView addAnnotation:self.pinAnnotation];

    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(self.selectedCoordinate, 1500.0, 1500.0);
    [self.mapView setRegion:region animated:NO];
    [self updateSearchCompleterRegion];
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
    // If the preview cell is visible, reload its section to update formatted coordinate readout
    if (self.panelTab == LSMapPickerPanelTabMap && self.coordinateMode == LSMapPickerCoordinateModeStatic) {
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)movePinToCoordinate:(CLLocationCoordinate2D)coordinate animated:(BOOL)animated {
    self.selectedCoordinate = coordinate;
    self.hasSelectedCoordinate = YES;
    self.suppressFieldSync = YES;
    self.latitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.latitude];
    self.longitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.longitude];
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
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return nil;
    }

    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });

    NSString *normalized = [trimmed stringByReplacingOccurrencesOfString:@"," withString:@"."];
    return [formatter numberFromString:normalized];
}

- (BOOL)applyFieldsToCoordinate {
    if (self.suppressFieldSync) {
        return YES;
    }

    NSNumber *latitudeNumber = [self ls_parsedCoordinateComponentFromText:self.latitudeField.text];
    NSNumber *longitudeNumber = [self ls_parsedCoordinateComponentFromText:self.longitudeField.text];
    if (!latitudeNumber || !longitudeNumber) {
        [self showInvalidCoordinateFeedback];
        return NO;
    }

    double latitude = latitudeNumber.doubleValue;
    double longitude = longitudeNumber.doubleValue;
    if (latitude < -90.0 || latitude > 90.0 || longitude < -180.0 || longitude > 180.0) {
        [self showInvalidCoordinateFeedback];
        return NO;
    }

    [self movePinToCoordinate:CLLocationCoordinate2DMake(latitude, longitude) animated:YES];
    return YES;
}

- (void)showInvalidCoordinateFeedback {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];

    // Provide visual shake animation on coordinates section
    UITableViewCell *latCell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
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
    PersistenceManager *store = [PersistenceManager shared];
    store.fluctuationEnabled = self.fluctuationSwitch.isOn;

    // Smoothly animate insertion or deletion of the radius row in Inset Grouped style
    NSIndexPath *radiusPath = [NSIndexPath indexPathForRow:1 inSection:3];
    [self.tableView beginUpdates];
    if (self.fluctuationSwitch.isOn) {
        [self.tableView insertRowsAtIndexPaths:@[radiusPath] withRowAnimation:UITableViewRowAnimationFade];
    } else {
        [self.tableView deleteRowsAtIndexPaths:@[radiusPath] withRowAnimation:UITableViewRowAnimationFade];
    }
    [self.tableView endUpdates];

    if (self.fluctuationSwitch.isOn) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.fluctuationRadiusField becomeFirstResponder];
        });
    }
}

- (void)handleFluctuationRadiusChanged {
    NSString *text = [self.fluctuationRadiusField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    double radius = 50.0;
    if (text.length > 0) {
        NSNumber *value = [self ls_parsedCoordinateComponentFromText:text];
        radius = value ? value.doubleValue : 50.0;
    } else {
        radius = [PersistenceManager shared].fluctuationRadius;
    }
    if (radius < 1.0) radius = 1.0;
    if (radius > 1000.0) radius = 1000.0;
    [PersistenceManager shared].fluctuationRadius = radius;
    self.fluctuationRadiusField.text = [NSString stringWithFormat:@"%.0f m", radius];
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
    [self hideSearchSuggestions];
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
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissKeyboard)];
    toolbar.items = @[flex, done];

    self.latitudeField.inputAccessoryView = toolbar;
    self.longitudeField.inputAccessoryView = toolbar;
    self.altitudeField.inputAccessoryView = toolbar;
    self.fluctuationRadiusField.inputAccessoryView = toolbar;
    self.customSpeedField.inputAccessoryView = toolbar;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
    [self hideSearchSuggestions];
}

- (void)textFieldDidChange:(UITextField *)textField {
    if (textField == self.customSpeedField) {
        NSNumber *parsed = [self ls_parsedCoordinateComponentFromText:textField.text];
        BOOL valid = parsed && parsed.doubleValue >= 1.0 && parsed.doubleValue <= 500.0;
        textField.textColor = valid ? UIColor.labelColor : UIColor.systemRedColor;
        return;
    }
    [self applyFieldsToCoordinate];
}

- (void)ls_keyboardWillShow:(NSNotification *)note {
    CGRect kbFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat kbHeight = kbFrame.size.height;
    UIEdgeInsets insets = self.tableView.contentInset;
    insets.bottom = kbHeight;
    self.tableView.contentInset = insets;
    self.tableView.scrollIndicatorInsets = insets;
}

- (void)ls_keyboardWillHide:(NSNotification *)note {
    (void)note;
    UIEdgeInsets insets = self.tableView.contentInset;
    insets.bottom = 0.0;
    self.tableView.contentInset = insets;
    self.tableView.scrollIndicatorInsets = insets;
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

    [store recordRecentCoordinate:self.selectedCoordinate name:nil];
    [self playApplyHaptic];
    LSSetHooksBypassed(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleStopSpoofing {
    [[LSRouteSimulator shared] stop];
    [[PersistenceManager shared] clearSpoof];
    [PersistenceManager shared].simulationWasActive = NO;
    [self playSimulationStopHaptic];
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
        view.glyphImage = [UIImage systemImageNamed:@"mappin.and.ellipse"];
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

    // Static mode: 5 sections
    // 0: Target Coordinate Preview & Bookmark button
    // 1: Coordinate Inputs (Lat, Lon, Alt) with Apple SF symbols
    // 2: Heading & Bearing (Heading slider)
    // 3: Options (Fluctuation, Radius if on, Keep Last, Show Real)
    // 4: Action Buttons (Apply, Stop if active, Cancel)
    return 5;
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
        case 0: return 1; // Preview & Bookmark
        case 1: return 3; // Latitude, Longitude, Altitude
        case 2: return 1; // Heading slider
        case 3: return self.fluctuationSwitch.isOn ? 4 : 3; // Fluctuation, (Radius), Keep Last, Show Real
        case 4: return [[PersistenceManager shared] isSpoofingEnabled] ? 3 : 2; // Apply, (Stop), Cancel
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
        case 0: return @"Selected Location";
        case 1: return @"Coordinates";
        case 2: return @"Bearing & Direction";
        case 3: return @"Spoofing Options";
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
    // Search suggestions table view cells
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
            content.image = [UIImage systemImageNamed:@"mappin.circle.fill"];
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

    // Static mode
    return [self ls_staticCellForIndexPath:indexPath];
}

- (UITableViewCell *)ls_staticCellForIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0: { // Section 0: Target Coordinate Preview & Bookmark Button
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UIView *badge = [MapPickerViewController iconBadgeWithSymbolName:@"mappin.and.ellipse" backgroundColor:UIColor.systemRedColor];
            badge.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:badge];

            UILabel *title = [[UILabel alloc] init];
            title.translatesAutoresizingMaskIntoConstraints = NO;
            title.text = @"Target Coordinate";
            title.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
            title.textColor = UIColor.labelColor;
            [cell.contentView addSubview:title];

            UILabel *coordLabel = [[UILabel alloc] init];
            coordLabel.translatesAutoresizingMaskIntoConstraints = NO;
            coordLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
            coordLabel.textColor = UIColor.secondaryLabelColor;
            coordLabel.text = [NSString stringWithFormat:@"%@%.6f, %@%.6f",
                               self.selectedCoordinate.latitude >= 0 ? @"N " : @"S ",
                               fabs(self.selectedCoordinate.latitude),
                               self.selectedCoordinate.longitude >= 0 ? @"E " : @"W ",
                               fabs(self.selectedCoordinate.longitude)];
            [cell.contentView addSubview:coordLabel];

            UIButton *bmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
            bmBtn.translatesAutoresizingMaskIntoConstraints = NO;
            UIImage *bmIcon = [UIImage systemImageNamed:@"bookmark.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18.0 weight:UIFontWeightSemibold]];
            [bmBtn setImage:bmIcon forState:UIControlStateNormal];
            bmBtn.tintColor = UIColor.systemYellowColor;
            bmBtn.accessibilityLabel = @"Save Bookmark";
            [bmBtn addTarget:self action:@selector(handleBookmarkSaveTapped) forControlEvents:UIControlEventTouchUpInside];
            [cell.contentView addSubview:bmBtn];

            [NSLayoutConstraint activateConstraints:@[
                [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                [title.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
                [title.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],

                [coordLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
                [coordLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3.0],
                [coordLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
                [coordLabel.trailingAnchor constraintLessThanOrEqualToAnchor:bmBtn.leadingAnchor constant:-8.0],

                [bmBtn.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                [bmBtn.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [bmBtn.widthAnchor constraintEqualToConstant:36.0],
                [bmBtn.heightAnchor constraintEqualToConstant:36.0]
            ]];
            return cell;
        }

        case 1: { // Section 1: Coordinate Inputs (Lat, Lon, Alt)
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UIView *badge = nil;
            NSString *labelText = @"";
            UITextField *inputField = nil;

            if (indexPath.row == 0) {
                badge = [MapPickerViewController iconBadgeWithSymbolName:@"location.north.fill" backgroundColor:UIColor.systemBlueColor];
                labelText = @"Latitude";
                inputField = self.latitudeField;
            } else if (indexPath.row == 1) {
                badge = [MapPickerViewController iconBadgeWithSymbolName:@"globe.americas.fill" backgroundColor:UIColor.systemTealColor];
                labelText = @"Longitude";
                inputField = self.longitudeField;
            } else {
                badge = [MapPickerViewController iconBadgeWithSymbolName:@"mountain.2.fill" backgroundColor:UIColor.systemOrangeColor];
                labelText = @"Altitude";
                inputField = self.altitudeField;
            }

            badge.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:badge];

            UILabel *lbl = [[UILabel alloc] init];
            lbl.translatesAutoresizingMaskIntoConstraints = NO;
            lbl.text = labelText;
            lbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
            lbl.textColor = UIColor.labelColor;
            [cell.contentView addSubview:lbl];

            [inputField removeFromSuperview];
            inputField.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:inputField];

            [NSLayoutConstraint activateConstraints:@[
                [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
                [lbl.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [lbl.widthAnchor constraintEqualToConstant:85.0],

                [inputField.leadingAnchor constraintEqualToAnchor:lbl.trailingAnchor constant:8.0],
                [inputField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                [inputField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [inputField.heightAnchor constraintEqualToConstant:40.0],
                [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:48.0]
            ]];
            return cell;
        }

        case 2: { // Section 2: Heading Slider & Direction
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            UIView *badge = [MapPickerViewController iconBadgeWithSymbolName:@"safari.fill" backgroundColor:UIColor.systemIndigoColor];
            badge.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:badge];

            UILabel *lbl = [[UILabel alloc] init];
            lbl.translatesAutoresizingMaskIntoConstraints = NO;
            lbl.text = @"Heading";
            lbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
            lbl.textColor = UIColor.labelColor;
            [cell.contentView addSubview:lbl];

            [self.headingValueLabel removeFromSuperview];
            self.headingValueLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:self.headingValueLabel];

            [self.headingSlider removeFromSuperview];
            self.headingSlider.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:self.headingSlider];

            [NSLayoutConstraint activateConstraints:@[
                [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                [badge.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12.0],

                [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
                [lbl.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],

                [self.headingValueLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                [self.headingValueLabel.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
                [self.headingValueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:lbl.trailingAnchor constant:8.0],

                [self.headingSlider.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:12.0],
                [self.headingSlider.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                [self.headingSlider.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                [self.headingSlider.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14.0]
            ]];
            return cell;
        }

        case 3: { // Section 3: Options (Fluctuation, Radius, Keep Last, Show Real)
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            NSInteger row = indexPath.row;
            // If fluctuation is ON: row 0=Fluctuation, 1=Radius, 2=Keep Last, 3=Show Real
            // If fluctuation is OFF: row 0=Fluctuation, 1=Keep Last, 2=Show Real
            if (row == 0) {
                UIView *badge = [MapPickerViewController iconBadgeWithSymbolName:@"waveform.path" backgroundColor:UIColor.systemPurpleColor];
                badge.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:badge];

                UILabel *lbl = [[UILabel alloc] init];
                lbl.translatesAutoresizingMaskIntoConstraints = NO;
                lbl.text = @"Location Fluctuation";
                lbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
                lbl.textColor = UIColor.labelColor;
                [cell.contentView addSubview:lbl];

                UILabel *sub = [[UILabel alloc] init];
                sub.translatesAutoresizingMaskIntoConstraints = NO;
                sub.text = @"Adds subtle randomized GPS drift";
                sub.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
                sub.textColor = UIColor.secondaryLabelColor;
                [cell.contentView addSubview:sub];

                [self.fluctuationSwitch removeFromSuperview];
                self.fluctuationSwitch.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:self.fluctuationSwitch];

                [NSLayoutConstraint activateConstraints:@[
                    [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                    [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                    [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
                    [lbl.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],

                    [sub.leadingAnchor constraintEqualToAnchor:lbl.leadingAnchor],
                    [sub.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:2.0],
                    [sub.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
                    [sub.trailingAnchor constraintLessThanOrEqualToAnchor:self.fluctuationSwitch.leadingAnchor constant:-8.0],

                    [self.fluctuationSwitch.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                    [self.fluctuationSwitch.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
                ]];
                return cell;
            } else if (row == 1 && self.fluctuationSwitch.isOn) {
                // Radius input
                UIView *badge = [MapPickerViewController iconBadgeWithSymbolName:@"circle.dashed" backgroundColor:[UIColor.systemPurpleColor colorWithAlphaComponent:0.75]];
                badge.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:badge];

                UILabel *lbl = [[UILabel alloc] init];
                lbl.translatesAutoresizingMaskIntoConstraints = NO;
                lbl.text = @"Drift Radius (m)";
                lbl.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
                lbl.textColor = UIColor.labelColor;
                [cell.contentView addSubview:lbl];

                [self.fluctuationRadiusField removeFromSuperview];
                self.fluctuationRadiusField.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:self.fluctuationRadiusField];

                [NSLayoutConstraint activateConstraints:@[
                    [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                    [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                    [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
                    [lbl.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                    [self.fluctuationRadiusField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                    [self.fluctuationRadiusField.leadingAnchor constraintEqualToAnchor:lbl.trailingAnchor constant:8.0],
                    [self.fluctuationRadiusField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                    [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:46.0]
                ]];
                return cell;
            } else {
                // Keep Last or Show Real
                BOOL isKeepLast = (self.fluctuationSwitch.isOn ? row == 2 : row == 1);
                UIView *badge = isKeepLast ?
                    [MapPickerViewController iconBadgeWithSymbolName:@"clock.arrow.circlepath" backgroundColor:UIColor.systemGreenColor] :
                    [MapPickerViewController iconBadgeWithSymbolName:@"location.fill.viewfinder" backgroundColor:UIColor.systemBlueColor];
                badge.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:badge];

                UILabel *lbl = [[UILabel alloc] init];
                lbl.translatesAutoresizingMaskIntoConstraints = NO;
                lbl.text = isKeepLast ? @"Keep Last Location" : @"Show Real Location";
                lbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
                lbl.textColor = UIColor.labelColor;
                [cell.contentView addSubview:lbl];

                UILabel *sub = [[UILabel alloc] init];
                sub.translatesAutoresizingMaskIntoConstraints = NO;
                sub.text = isKeepLast ? @"Persist coordinate across app relaunches" : @"Display native GPS blue dot on map";
                sub.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
                sub.textColor = UIColor.secondaryLabelColor;
                [cell.contentView addSubview:sub];

                UISwitch *sw = isKeepLast ? self.keepLastSpoofSwitch : self.showRealLocationSwitch;
                [sw removeFromSuperview];
                sw.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:sw];

                [NSLayoutConstraint activateConstraints:@[
                    [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                    [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                    [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
                    [lbl.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],

                    [sub.leadingAnchor constraintEqualToAnchor:lbl.leadingAnchor],
                    [sub.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:2.0],
                    [sub.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
                    [sub.trailingAnchor constraintLessThanOrEqualToAnchor:sw.leadingAnchor constant:-8.0],

                    [sw.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                    [sw.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
                ]];
                return cell;
            }
        }

        case 4: { // Section 4: Action Buttons (Apply, Stop if active, Cancel)
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = UIColor.clearColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            BOOL isSpoofingActive = [[PersistenceManager shared] isSpoofingEnabled];
            NSInteger row = indexPath.row;

            UIView *btnView = nil;
            if (row == 0) {
                [self.applyButton removeFromSuperview];
                btnView = self.applyButton;
            } else if (row == 1 && isSpoofingActive) {
                [self.stopButton removeFromSuperview];
                btnView = self.stopButton;
            } else {
                [self.cancelButton removeFromSuperview];
                btnView = self.cancelButton;
            }

            [cell.contentView addSubview:btnView];
            [NSLayoutConstraint activateConstraints:@[
                [btnView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [btnView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [btnView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
                [btnView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0],
                [btnView.heightAnchor constraintEqualToConstant:48.0]
            ]];
            return cell;
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
