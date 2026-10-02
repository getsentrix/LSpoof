#import "MapPickerViewController+Private.h"
#import "PersistenceManager.h"
#import "RouteSimulator.h"

@implementation LSStartAnnotation
@end

@implementation LSDestinationAnnotation
@end

@implementation MapPickerViewController (LSRouteUI)

- (void)buildRouteControls {
    // Get Route Button
    self.getRouteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.getRouteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.getRouteButton setTitle:@"  Get Route Directions" forState:UIControlStateNormal];
    [self.getRouteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.getRouteButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    UIImage *routeIcon = [MapPickerViewController systemImageNamedWithFallback:@"arrow.triangle.turn.up.right.diamond.fill"
                                                                 configuration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIFontWeightBold]];
    [self.getRouteButton setImage:routeIcon forState:UIControlStateNormal];
    self.getRouteButton.tintColor = UIColor.whiteColor;
    self.getRouteButton.backgroundColor = UIColor.systemBlueColor;
    self.getRouteButton.layer.cornerRadius = 16.0;
    self.getRouteButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.getRouteButton addTarget:self action:@selector(handleGetRouteTapped) forControlEvents:UIControlEventTouchUpInside];

    self.routeSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.routeSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.routeSpinner.hidesWhenStopped = YES;
    self.routeSpinner.color = UIColor.whiteColor;
    [self.getRouteButton addSubview:self.routeSpinner];
    [NSLayoutConstraint activateConstraints:@[
        [self.routeSpinner.centerYAnchor constraintEqualToAnchor:self.getRouteButton.centerYAnchor],
        [self.routeSpinner.trailingAnchor constraintEqualToAnchor:self.getRouteButton.trailingAnchor constant:-16.0]
    ]];

    // Transport Mode Segment
    self.transportModeSegment = [[UISegmentedControl alloc] initWithItems:@[@"Walk", @"Cycle", @"Drive", @"Custom"]];
    self.transportModeSegment.translatesAutoresizingMaskIntoConstraints = NO;
    self.transportModeSegment.selectedSegmentIndex = 0;
    [self.transportModeSegment addTarget:self action:@selector(handleTransportModeChanged:) forControlEvents:UIControlEventValueChanged];

    // Custom speed text field
    self.customSpeedField = [[UITextField alloc] init];
    self.customSpeedField.translatesAutoresizingMaskIntoConstraints = NO;
    self.customSpeedField.placeholder = @"e.g. 25";
    self.customSpeedField.keyboardType = UIKeyboardTypeDecimalPad;
    self.customSpeedField.text = @"30 km/h";
    self.customSpeedField.textAlignment = NSTextAlignmentRight;
    self.customSpeedField.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightRegular];
    self.customSpeedField.textColor = UIColor.labelColor;
    self.customSpeedField.delegate = self;
    [self.customSpeedField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    UIToolbar *speedToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    speedToolbar.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(dismissCustomSpeedKeyboard)]
    ];
    [speedToolbar sizeToFit];
    self.customSpeedField.inputAccessoryView = speedToolbar;

    // Play Route Button
    self.playRouteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playRouteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playRouteButton setTitle:@"  Start Simulation" forState:UIControlStateNormal];
    [self.playRouteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.playRouteButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    UIImage *playIcon = [MapPickerViewController systemImageNamedWithFallback:@"play.fill"
                                                                configuration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIFontWeightBold]];
    [self.playRouteButton setImage:playIcon forState:UIControlStateNormal];
    self.playRouteButton.tintColor = UIColor.whiteColor;
    self.playRouteButton.backgroundColor = UIColor.systemGreenColor;
    self.playRouteButton.layer.cornerRadius = 16.0;
    self.playRouteButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.playRouteButton addTarget:self action:@selector(handlePlayRouteTapped) forControlEvents:UIControlEventTouchUpInside];

    // Pause Route Button
    self.pauseRouteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pauseRouteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pauseRouteButton setTitle:@"  Pause" forState:UIControlStateNormal];
    [self.pauseRouteButton setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    self.pauseRouteButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    UIImage *pauseIcon = [MapPickerViewController systemImageNamedWithFallback:@"pause.fill"
                                                                 configuration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIFontWeightSemibold]];
    [self.pauseRouteButton setImage:pauseIcon forState:UIControlStateNormal];
    self.pauseRouteButton.tintColor = UIColor.labelColor;
    self.pauseRouteButton.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.pauseRouteButton.layer.cornerRadius = 16.0;
    self.pauseRouteButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.pauseRouteButton.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.pauseRouteButton.layer.borderColor = UIColor.separatorColor.CGColor;
    [self.pauseRouteButton addTarget:self action:@selector(handlePauseRouteTapped) forControlEvents:UIControlEventTouchUpInside];

    // Stop Route Button
    self.stopRouteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopRouteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stopRouteButton setTitle:@"  Stop Route" forState:UIControlStateNormal];
    [self.stopRouteButton setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    self.stopRouteButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    UIImage *stopIcon = [MapPickerViewController systemImageNamedWithFallback:@"stop.fill"
                                                                configuration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIFontWeightSemibold]];
    [self.stopRouteButton setImage:stopIcon forState:UIControlStateNormal];
    self.stopRouteButton.tintColor = UIColor.systemRedColor;
    self.stopRouteButton.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    self.stopRouteButton.layer.cornerRadius = 16.0;
    self.stopRouteButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.stopRouteButton.layer.borderWidth = 1.0;
    self.stopRouteButton.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.4].CGColor;
    [self.stopRouteButton addTarget:self action:@selector(handleStopRouteTapped) forControlEvents:UIControlEventTouchUpInside];

    // Build Retained Route Static Cells
    // Start cell
    self.routeStartCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    self.routeStartCell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.routeStartCell.selectionStyle = UITableViewCellSelectionStyleDefault;

    UIView *startBadge = [MapPickerViewController iconBadgeWithSymbolName:@"flag.fill" backgroundColor:UIColor.systemGreenColor];
    [self.routeStartCell.contentView addSubview:startBadge];

    UILabel *startTitle = [[UILabel alloc] init];
    startTitle.translatesAutoresizingMaskIntoConstraints = NO;
    startTitle.text = @"Start Point";
    startTitle.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    startTitle.textColor = UIColor.labelColor;
    [self.routeStartCell.contentView addSubview:startTitle];

    self.routeStartSubLabel = [[UILabel alloc] init];
    self.routeStartSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.routeStartSubLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    self.routeStartSubLabel.textColor = UIColor.secondaryLabelColor;
    self.routeStartSubLabel.numberOfLines = 0;
    self.routeStartSubLabel.text = @"Tap to search or tap map";
    [self.routeStartCell.contentView addSubview:self.routeStartSubLabel];

    UIImageSymbolConfiguration *searchConfig = [UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIFontWeightSemibold];
    self.searchStartButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.searchStartButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *searchImg = [MapPickerViewController systemImageNamedWithFallback:@"magnifyingglass" configuration:searchConfig];
    [self.searchStartButton setImage:searchImg forState:UIControlStateNormal];
    self.searchStartButton.tintColor = UIColor.systemGreenColor;
    self.searchStartButton.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.12];
    self.searchStartButton.layer.cornerRadius = 16.0;
    self.searchStartButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.searchStartButton addTarget:self action:@selector(handleSearchStartTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.routeStartCell.contentView addSubview:self.searchStartButton];

    self.snapStartButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.snapStartButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageSymbolConfiguration *reticleConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIFontWeightSemibold];
    UIImage *reticleImg = [UIImage systemImageNamed:@"location.fill.viewfinder" withConfiguration:reticleConfig];
    if (!reticleImg) reticleImg = [UIImage systemImageNamed:@"location.circle.fill" withConfiguration:reticleConfig];
    [self.snapStartButton setImage:reticleImg forState:UIControlStateNormal];
    self.snapStartButton.tintColor = UIColor.systemGreenColor;
    self.snapStartButton.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.12];
    self.snapStartButton.layer.cornerRadius = 16.0;
    self.snapStartButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.snapStartButton addTarget:self action:@selector(handleSnapStartToCurrentLocation) forControlEvents:UIControlEventTouchUpInside];
    [self.routeStartCell.contentView addSubview:self.snapStartButton];

    [NSLayoutConstraint activateConstraints:@[
        [startBadge.leadingAnchor constraintEqualToAnchor:self.routeStartCell.contentView.leadingAnchor constant:16.0],
        [startBadge.centerYAnchor constraintEqualToAnchor:self.routeStartCell.contentView.centerYAnchor],

        [self.searchStartButton.trailingAnchor constraintEqualToAnchor:self.routeStartCell.contentView.trailingAnchor constant:-16.0],
        [self.searchStartButton.centerYAnchor constraintEqualToAnchor:self.routeStartCell.contentView.centerYAnchor],
        [self.searchStartButton.widthAnchor constraintEqualToConstant:34.0],
        [self.searchStartButton.heightAnchor constraintEqualToConstant:34.0],

        [self.snapStartButton.trailingAnchor constraintEqualToAnchor:self.searchStartButton.leadingAnchor constant:-8.0],
        [self.snapStartButton.centerYAnchor constraintEqualToAnchor:self.routeStartCell.contentView.centerYAnchor],
        [self.snapStartButton.widthAnchor constraintEqualToConstant:34.0],
        [self.snapStartButton.heightAnchor constraintEqualToConstant:34.0],

        [startTitle.leadingAnchor constraintEqualToAnchor:startBadge.trailingAnchor constant:12.0],
        [startTitle.topAnchor constraintEqualToAnchor:self.routeStartCell.contentView.topAnchor constant:12.0],
        [startTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.snapStartButton.leadingAnchor constant:-8.0],

        [self.routeStartSubLabel.leadingAnchor constraintEqualToAnchor:startTitle.leadingAnchor],
        [self.routeStartSubLabel.topAnchor constraintEqualToAnchor:startTitle.bottomAnchor constant:4.0],
        [self.routeStartSubLabel.bottomAnchor constraintEqualToAnchor:self.routeStartCell.contentView.bottomAnchor constant:-12.0],
        [self.routeStartSubLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.snapStartButton.leadingAnchor constant:-8.0]
    ]];

    // Dest cell
    self.routeDestCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    self.routeDestCell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.routeDestCell.selectionStyle = UITableViewCellSelectionStyleDefault;

    UIView *destBadge = [MapPickerViewController iconBadgeWithSymbolName:@"flag.checkered" backgroundColor:UIColor.systemRedColor];
    [self.routeDestCell.contentView addSubview:destBadge];

    UILabel *destTitle = [[UILabel alloc] init];
    destTitle.translatesAutoresizingMaskIntoConstraints = NO;
    destTitle.text = @"Destination";
    destTitle.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    destTitle.textColor = UIColor.labelColor;
    [self.routeDestCell.contentView addSubview:destTitle];

    self.routeDestSubLabel = [[UILabel alloc] init];
    self.routeDestSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.routeDestSubLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    self.routeDestSubLabel.textColor = UIColor.secondaryLabelColor;
    self.routeDestSubLabel.numberOfLines = 0;
    self.routeDestSubLabel.text = @"Tap to search or tap map";
    [self.routeDestCell.contentView addSubview:self.routeDestSubLabel];

    self.searchDestButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.searchDestButton.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *destSearchImg = [MapPickerViewController systemImageNamedWithFallback:@"magnifyingglass" configuration:searchConfig];
    [self.searchDestButton setImage:destSearchImg forState:UIControlStateNormal];
    self.searchDestButton.tintColor = UIColor.systemRedColor;
    self.searchDestButton.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    self.searchDestButton.layer.cornerRadius = 16.0;
    self.searchDestButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.searchDestButton addTarget:self action:@selector(handleSearchDestinationTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.routeDestCell.contentView addSubview:self.searchDestButton];

    [NSLayoutConstraint activateConstraints:@[
        [destBadge.leadingAnchor constraintEqualToAnchor:self.routeDestCell.contentView.leadingAnchor constant:16.0],
        [destBadge.centerYAnchor constraintEqualToAnchor:self.routeDestCell.contentView.centerYAnchor],

        [self.searchDestButton.trailingAnchor constraintEqualToAnchor:self.routeDestCell.contentView.trailingAnchor constant:-16.0],
        [self.searchDestButton.centerYAnchor constraintEqualToAnchor:self.routeDestCell.contentView.centerYAnchor],
        [self.searchDestButton.widthAnchor constraintEqualToConstant:34.0],
        [self.searchDestButton.heightAnchor constraintEqualToConstant:34.0],

        [destTitle.leadingAnchor constraintEqualToAnchor:destBadge.trailingAnchor constant:12.0],
        [destTitle.topAnchor constraintEqualToAnchor:self.routeDestCell.contentView.topAnchor constant:12.0],
        [destTitle.trailingAnchor constraintLessThanOrEqualToAnchor:self.searchDestButton.leadingAnchor constant:-8.0],

        [self.routeDestSubLabel.leadingAnchor constraintEqualToAnchor:destTitle.leadingAnchor],
        [self.routeDestSubLabel.topAnchor constraintEqualToAnchor:destTitle.bottomAnchor constant:4.0],
        [self.routeDestSubLabel.bottomAnchor constraintEqualToAnchor:self.routeDestCell.contentView.bottomAnchor constant:-12.0],
        [self.routeDestSubLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.searchDestButton.leadingAnchor constant:-8.0]
    ]];

    // Get directions cell
    self.routeGetDirectionsCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.routeGetDirectionsCell.backgroundColor = UIColor.clearColor;
    self.routeGetDirectionsCell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    self.routeGetDirectionsCell.selectionStyle = UITableViewCellSelectionStyleNone;
    self.routeGetDirectionsCell.separatorInset = UIEdgeInsetsMake(0, 10000, 0, 0);

    [self.routeGetDirectionsCell.contentView addSubview:self.getRouteButton];
    [NSLayoutConstraint activateConstraints:@[
        [self.getRouteButton.leadingAnchor constraintEqualToAnchor:self.routeGetDirectionsCell.contentView.leadingAnchor constant:4.0],
        [self.getRouteButton.trailingAnchor constraintEqualToAnchor:self.routeGetDirectionsCell.contentView.trailingAnchor constant:-4.0],
        [self.getRouteButton.topAnchor constraintEqualToAnchor:self.routeGetDirectionsCell.contentView.topAnchor constant:12.0],
        [self.getRouteButton.bottomAnchor constraintEqualToAnchor:self.routeGetDirectionsCell.contentView.bottomAnchor constant:-16.0],
        [self.getRouteButton.heightAnchor constraintEqualToConstant:52.0]
    ]];

    // Transport mode cell
    self.routeTransportCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.routeTransportCell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.routeTransportCell.selectionStyle = UITableViewCellSelectionStyleNone;

    [self.routeTransportCell.contentView addSubview:self.transportModeSegment];
    [NSLayoutConstraint activateConstraints:@[
        [self.transportModeSegment.leadingAnchor constraintEqualToAnchor:self.routeTransportCell.contentView.leadingAnchor constant:16.0],
        [self.transportModeSegment.trailingAnchor constraintEqualToAnchor:self.routeTransportCell.contentView.trailingAnchor constant:-16.0],
        [self.transportModeSegment.topAnchor constraintEqualToAnchor:self.routeTransportCell.contentView.topAnchor constant:8.0],
        [self.transportModeSegment.bottomAnchor constraintEqualToAnchor:self.routeTransportCell.contentView.bottomAnchor constant:-8.0],
        [self.transportModeSegment.heightAnchor constraintEqualToConstant:32.0]
    ]];

    // Custom speed cell
    self.routeCustomSpeedCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.routeCustomSpeedCell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.routeCustomSpeedCell.selectionStyle = UITableViewCellSelectionStyleNone;

    UIView *spdBadge = [MapPickerViewController iconBadgeWithSymbolName:@"speedometer" backgroundColor:UIColor.systemOrangeColor];
    [self.routeCustomSpeedCell.contentView addSubview:spdBadge];

    UILabel *spdLbl = [[UILabel alloc] init];
    spdLbl.translatesAutoresizingMaskIntoConstraints = NO;
    spdLbl.text = @"Speed";
    spdLbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
    spdLbl.textColor = UIColor.labelColor;
    [self.routeCustomSpeedCell.contentView addSubview:spdLbl];

    [self.routeCustomSpeedCell.contentView addSubview:self.customSpeedField];
    [NSLayoutConstraint activateConstraints:@[
        [spdBadge.leadingAnchor constraintEqualToAnchor:self.routeCustomSpeedCell.contentView.leadingAnchor constant:16.0],
        [spdBadge.centerYAnchor constraintEqualToAnchor:self.routeCustomSpeedCell.contentView.centerYAnchor],

        [spdLbl.leadingAnchor constraintEqualToAnchor:spdBadge.trailingAnchor constant:12.0],
        [spdLbl.centerYAnchor constraintEqualToAnchor:self.routeCustomSpeedCell.contentView.centerYAnchor],
        [spdLbl.widthAnchor constraintEqualToConstant:90.0],

        [self.customSpeedField.leadingAnchor constraintEqualToAnchor:spdLbl.trailingAnchor constant:8.0],
        [self.customSpeedField.trailingAnchor constraintEqualToAnchor:self.routeCustomSpeedCell.contentView.trailingAnchor constant:-16.0],
        [self.customSpeedField.centerYAnchor constraintEqualToAnchor:self.routeCustomSpeedCell.contentView.centerYAnchor],
        [self.customSpeedField.topAnchor constraintEqualToAnchor:self.routeCustomSpeedCell.contentView.topAnchor constant:6.0],
        [self.customSpeedField.bottomAnchor constraintEqualToAnchor:self.routeCustomSpeedCell.contentView.bottomAnchor constant:-6.0],
        [self.customSpeedField.heightAnchor constraintGreaterThanOrEqualToConstant:36.0]
    ]];

    // Playback cell
    self.routePlaybackCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.routePlaybackCell.backgroundColor = UIColor.clearColor;
    self.routePlaybackCell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    self.routePlaybackCell.selectionStyle = UITableViewCellSelectionStyleNone;
    self.routePlaybackCell.separatorInset = UIEdgeInsetsMake(0, 10000, 0, 0);

    // Cancel cell
    self.routeCancelCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    self.routeCancelCell.backgroundColor = UIColor.clearColor;
    self.routeCancelCell.backgroundConfiguration = [UIBackgroundConfiguration clearConfiguration];
    self.routeCancelCell.selectionStyle = UITableViewCellSelectionStyleNone;
    self.routeCancelCell.separatorInset = UIEdgeInsetsMake(0, 10000, 0, 0);

    [self ls_updateRoutePlaybackCell];
}

- (void)ls_updateRoutePlaybackCell {
    for (UIView *v in self.routePlaybackCell.contentView.subviews) {
        [v removeFromSuperview];
    }

    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (!simulator.isSimulating) {
        [self.routePlaybackCell.contentView addSubview:self.playRouteButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.playRouteButton.leadingAnchor constraintEqualToAnchor:self.routePlaybackCell.contentView.leadingAnchor constant:4.0],
            [self.playRouteButton.trailingAnchor constraintEqualToAnchor:self.routePlaybackCell.contentView.trailingAnchor constant:-4.0],
            [self.playRouteButton.topAnchor constraintEqualToAnchor:self.routePlaybackCell.contentView.topAnchor constant:12.0],
            [self.playRouteButton.bottomAnchor constraintEqualToAnchor:self.routePlaybackCell.contentView.bottomAnchor constant:-16.0],
            [self.playRouteButton.heightAnchor constraintEqualToConstant:52.0]
        ]];
    } else {
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.pauseRouteButton, self.stopRouteButton]];
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 12.0;
        stack.distribution = UIStackViewDistributionFillEqually;
        [self.routePlaybackCell.contentView addSubview:stack];

        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.routePlaybackCell.contentView.leadingAnchor constant:4.0],
            [stack.trailingAnchor constraintEqualToAnchor:self.routePlaybackCell.contentView.trailingAnchor constant:-4.0],
            [stack.topAnchor constraintEqualToAnchor:self.routePlaybackCell.contentView.topAnchor constant:12.0],
            [stack.bottomAnchor constraintEqualToAnchor:self.routePlaybackCell.contentView.bottomAnchor constant:-16.0],
            [stack.heightAnchor constraintEqualToConstant:52.0]
        ]];
    }
}

- (void)ls_updateRouteWaypointLabels {
    if (self.startAnnotation && CLLocationCoordinate2DIsValid(self.startAnnotation.coordinate)) {
        if (self.startWaypointName.length > 0) {
            self.routeStartSubLabel.text = [NSString stringWithFormat:@"%@\n%.6f, %.6f",
                                            self.startWaypointName,
                                            self.startAnnotation.coordinate.latitude,
                                            self.startAnnotation.coordinate.longitude];
        } else {
            self.routeStartSubLabel.text = [NSString stringWithFormat:@"%.6f, %.6f",
                                            self.startAnnotation.coordinate.latitude,
                                            self.startAnnotation.coordinate.longitude];
        }
    } else {
        self.routeStartSubLabel.text = @"Tap to search or tap map";
    }

    if (self.destinationAnnotation && CLLocationCoordinate2DIsValid(self.destinationAnnotation.coordinate)) {
        if (self.destinationWaypointName.length > 0) {
            self.routeDestSubLabel.text = [NSString stringWithFormat:@"%@\n%.6f, %.6f",
                                            self.destinationWaypointName,
                                            self.destinationAnnotation.coordinate.latitude,
                                            self.destinationAnnotation.coordinate.longitude];
        } else {
            self.routeDestSubLabel.text = [NSString stringWithFormat:@"%.6f, %.6f",
                                            self.destinationAnnotation.coordinate.latitude,
                                            self.destinationAnnotation.coordinate.longitude];
        }
    } else {
        self.routeDestSubLabel.text = @"Tap to search or tap map";
    }
}

- (void)updateCoordinateModeVisibility {
    BOOL routeMode = self.coordinateMode == LSMapPickerCoordinateModeRoute;

    if (routeMode) {
        if (self.pinAnnotation) {
            [self.mapView removeAnnotation:self.pinAnnotation];
        }
        if (!self.startAnnotation) {
            self.routePlacementPhase = LSRoutePlacementPhaseStart;
            self.mapHintLabel.text = @"  Tap map for route start  ";
        }
    } else {
        if (![[LSRouteSimulator shared] isSimulating]) {
            [self ls_clearRouteAnnotationsAndOverlay];
            self.mapHintLabel.text = @"  Tap map or drag pin  ";
        }
        if (self.pinAnnotation && self.mapConfigured) {
            [self.mapView addAnnotation:self.pinAnnotation];
        }
    }

    [self ls_updateRouteWaypointLabels];
    [self ls_updateRoutePlaybackCell];
    [self refreshStatusPill];
    [self.tableView reloadData];
}

- (void)ls_clearRouteAnnotationsAndOverlay {
    self.startWaypointName = nil;
    self.destinationWaypointName = nil;
    if (self.startAnnotation) {
        [self.mapView removeAnnotation:self.startAnnotation];
        self.startAnnotation = nil;
    }
    if (self.destinationAnnotation) {
        [self.mapView removeAnnotation:self.destinationAnnotation];
        self.destinationAnnotation = nil;
    }
    if (self.routePolyline) {
        [self.mapView removeOverlay:self.routePolyline];
        self.routePolyline = nil;
    }
    self.fetchedRoute = nil;
}

- (void)ls_handleRouteMapTap:(CLLocationCoordinate2D)coordinate {
    if (self.routePlacementPhase == LSRoutePlacementPhaseStart || !self.startAnnotation) {
        if (!self.startAnnotation) {
            self.startAnnotation = [[LSStartAnnotation alloc] init];
            self.startAnnotation.title = @"Start";
            [self.mapView addAnnotation:self.startAnnotation];
        }
        self.startAnnotation.coordinate = coordinate;
        self.startWaypointName = nil;
        self.routePlacementPhase = LSRoutePlacementPhaseDestination;
        self.mapHintLabel.text = @"  Tap map for destination  ";
    } else {
        if (!self.destinationAnnotation) {
            self.destinationAnnotation = [[LSDestinationAnnotation alloc] init];
            self.destinationAnnotation.title = @"Destination";
            [self.mapView addAnnotation:self.destinationAnnotation];
        }
        self.destinationAnnotation.coordinate = coordinate;
        self.destinationWaypointName = nil;
        self.routePlacementPhase = LSRoutePlacementPhaseStart;
        self.mapHintLabel.text = @"  Tap map to move start  ";
    }

    self.fetchedRoute = nil;
    if (self.routePolyline) {
        [self.mapView removeOverlay:self.routePolyline];
        self.routePolyline = nil;
    }

    [self ls_updateRouteWaypointLabels];
    [self ls_updateRoutePlaybackCell];
    [self.tableView reloadData];
}

- (MKDirectionsTransportType)ls_directionsTransportType {
    switch (self.transportModeSegment.selectedSegmentIndex) {
        case 0:
        case 1:
            return MKDirectionsTransportTypeWalking;
        case 2:
        case 3:
        default:
            return MKDirectionsTransportTypeAutomobile;
    }
}

- (LSTransportMode)ls_selectedTransportMode {
    switch (self.transportModeSegment.selectedSegmentIndex) {
        case 0: return LSTransportModeWalking;
        case 1: return LSTransportModeCycling;
        case 2: return LSTransportModeDriving;
        default: return LSTransportModeCustom;
    }
}

- (void)handleGetRouteTapped {
    if (!self.startAnnotation || !self.destinationAnnotation) {
        [self playRouteFailureHaptic];
        return;
    }

    [self.routeSpinner startAnimating];

    MKDirectionsRequest *request = [[MKDirectionsRequest alloc] init];
    request.source = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.startAnnotation.coordinate]];
    request.destination = [[MKMapItem alloc] initWithPlacemark:[[MKPlacemark alloc] initWithCoordinate:self.destinationAnnotation.coordinate]];
    request.transportType = [self ls_directionsTransportType];

    MKDirections *directions = [[MKDirections alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [directions calculateDirectionsWithCompletionHandler:^(MKDirectionsResponse * _Nullable response, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.routeSpinner stopAnimating];

            if (error || response.routes.count == 0) {
                [strongSelf playRouteFailureHaptic];
                strongSelf.statusLabel.text = @"Route fetch failed";
                __weak typeof(strongSelf) innerWeak = strongSelf;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [innerWeak refreshStatusPill];
                });
                return;
            }

            [strongSelf playRouteSuccessHaptic];
            strongSelf.fetchedRoute = response.routes.firstObject;
            if (strongSelf.routePolyline) {
                [strongSelf.mapView removeOverlay:strongSelf.routePolyline];
            }
            strongSelf.routePolyline = strongSelf.fetchedRoute.polyline;
            [strongSelf.mapView addOverlay:strongSelf.routePolyline];
            [strongSelf.mapView setVisibleMapRect:strongSelf.routePolyline.boundingMapRect edgePadding:UIEdgeInsetsMake(48, 48, 48, 48) animated:YES];
            [strongSelf ls_updateRouteWaypointLabels];
            [strongSelf ls_updateRoutePlaybackCell];
            [strongSelf.tableView reloadData];
            [strongSelf refreshStatusPill];
        });
    }];
}

- (void)handleTransportModeChanged:(UISegmentedControl *)sender {
    (void)sender;
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    simulator.transportMode = [self ls_selectedTransportMode];
    if (simulator.transportMode == LSTransportModeCustom) {
        NSNumber *parsed = [self ls_parsedCoordinateComponentFromText:self.customSpeedField.text];
        simulator.customSpeedKmh = parsed ? parsed.doubleValue : 30.0;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.customSpeedField becomeFirstResponder];
        });
    } else {
        [self.customSpeedField resignFirstResponder];
    }
    [self.tableView reloadData];
}

- (void)dismissCustomSpeedKeyboard {
    [self.customSpeedField resignFirstResponder];
    NSNumber *parsed = [self ls_parsedCoordinateComponentFromText:self.customSpeedField.text];
    double speedVal = parsed ? parsed.doubleValue : 30.0;
    if (speedVal < 1.0) speedVal = 1.0;
    if (speedVal > 300.0) speedVal = 300.0;
    self.customSpeedField.text = [NSString stringWithFormat:@"%.1f km/h", speedVal];
    [LSRouteSimulator shared].customSpeedKmh = speedVal;
}

- (void)handleSnapStartToCurrentLocation {
    CLLocationCoordinate2D snapCoordinate = kCLLocationCoordinate2DInvalid;
    if ([[PersistenceManager shared] isSpoofingEnabled] && [[PersistenceManager shared] hasStoredCoordinate]) {
        snapCoordinate = [[PersistenceManager shared] spoofCoordinate];
    } else if (self.pinAnnotation && CLLocationCoordinate2DIsValid(self.pinAnnotation.coordinate)) {
        snapCoordinate = self.pinAnnotation.coordinate;
    } else if ([PersistenceManager shared].hasRealCoordinate) {
        snapCoordinate = [PersistenceManager shared].lastRealCoordinate;
    } else if (self.mapView.userLocation && CLLocationCoordinate2DIsValid(self.mapView.userLocation.coordinate) &&
               fabs(self.mapView.userLocation.coordinate.latitude) > 0.0001) {
        snapCoordinate = self.mapView.userLocation.coordinate;
    }

    if (!CLLocationCoordinate2DIsValid(snapCoordinate)) {
        [self playRouteFailureHaptic];
        return;
    }

    if (!self.startAnnotation) {
        self.startAnnotation = [[LSStartAnnotation alloc] init];
        self.startAnnotation.title = @"Start";
        [self.mapView addAnnotation:self.startAnnotation];
    }
    self.startAnnotation.coordinate = snapCoordinate;
    self.startWaypointName = @"Current Location";
    self.routePlacementPhase = self.destinationAnnotation ? LSRoutePlacementPhaseStart : LSRoutePlacementPhaseDestination;
    self.mapHintLabel.text = self.destinationAnnotation ? @"  Tap Get Route Directions  " : @"  Tap map for destination  ";

    [self ls_updateRouteWaypointLabels];

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];

    if (self.destinationAnnotation && CLLocationCoordinate2DIsValid(self.destinationAnnotation.coordinate)) {
        [self handleGetRouteTapped];
    } else {
        [self.mapView setCenterCoordinate:snapCoordinate animated:YES];
    }
}

- (void)handlePlayRouteTapped {
    if (!self.fetchedRoute) {
        return;
    }

    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    simulator.delegate = self;
    simulator.transportMode = [self ls_selectedTransportMode];
    if (simulator.transportMode == LSTransportModeCustom) {
        NSNumber *parsed = [self ls_parsedCoordinateComponentFromText:self.customSpeedField.text];
        simulator.customSpeedKmh = MAX(parsed ? parsed.doubleValue : 30.0, 1.0);
    }

    CLLocationCoordinate2D start = self.startAnnotation.coordinate;
    if (!CLLocationCoordinate2DIsValid(start) ||
        ![[PersistenceManager shared] setSpoofCoordinate:start enabled:YES]) {
        [self playRouteFailureHaptic];
        self.statusLabel.text = @"Invalid route start";
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf refreshStatusPill];
        });
        return;
    }
    [PersistenceManager shared].simulationWasActive = YES;

    [simulator startWithRoute:self.fetchedRoute];
    [self ls_updateRoutePlaybackCell];
    [self refreshStatusPill];
    [self.tableView reloadData];
}

- (void)handlePauseRouteTapped {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (simulator.isPaused) {
        [simulator resume];
        [self.pauseRouteButton setTitle:@"  Pause" forState:UIControlStateNormal];
    } else {
        [simulator pause];
        [self.pauseRouteButton setTitle:@"  Resume" forState:UIControlStateNormal];
        CLLocationCoordinate2D coord = simulator.currentCoordinate;
        if (CLLocationCoordinate2DIsValid(coord)) {
            [[PersistenceManager shared] setSpoofCoordinate:coord enabled:YES];
        }
    }
}

- (void)handleStopRouteTapped {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    CLLocationCoordinate2D coord = simulator.currentCoordinate;
    if (CLLocationCoordinate2DIsValid(coord)) {
        [[PersistenceManager shared] setSpoofCoordinate:coord enabled:YES];
    }
    [simulator stop];
    [PersistenceManager shared].simulationWasActive = NO;
    [self playSimulationStopHaptic];
    [self ls_updateRoutePlaybackCell];
    [self refreshStatusPill];
    [self.tableView reloadData];
}

- (void)restoreSimulationUIIfNeeded {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (simulator.isSimulating) {
        [self restoreRouteUIFromSimulator];
        return;
    }

    if (![PersistenceManager shared].simulationWasActive) {
        return;
    }

    [PersistenceManager shared].simulationWasActive = NO;
    self.statusLabel.text = @"Previous route session expired";
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf refreshStatusPill];
    });
}

- (void)restoreRouteUIFromSimulator {
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    NSArray<LSRoutePoint *> *points = simulator.routePoints;
    if (points.count < 2) return;

    self.startAnnotation = [[LSStartAnnotation alloc] init];
    self.startAnnotation.title = @"Start";
    self.startAnnotation.coordinate = simulator.startCoordinate;
    [self.mapView addAnnotation:self.startAnnotation];

    self.destinationAnnotation = [[LSDestinationAnnotation alloc] init];
    self.destinationAnnotation.title = @"Destination";
    self.destinationAnnotation.coordinate = simulator.destinationCoordinate;
    [self.mapView addAnnotation:self.destinationAnnotation];

    NSUInteger count = points.count;
    CLLocationCoordinate2D *coords = malloc(sizeof(CLLocationCoordinate2D) * count);
    if (!coords) return;
    for (NSUInteger i = 0; i < count; i++) {
        coords[i] = points[i].coordinate;
    }
    self.routePolyline = [MKPolyline polylineWithCoordinates:coords count:count];
    free(coords);
    [self.mapView addOverlay:self.routePolyline];

    [self.mapView setVisibleMapRect:self.routePolyline.boundingMapRect
                        edgePadding:UIEdgeInsetsMake(48.0, 48.0, 48.0, 48.0)
                           animated:NO];

    if (self.pinAnnotation) {
        [self.mapView removeAnnotation:self.pinAnnotation];
    }

    self.coordinateMode = LSMapPickerCoordinateModeRoute;
    self.panelTab = LSMapPickerPanelTabRoute;
    self.panelTabSegment.selectedSegmentIndex = 1;
    self.coordinateModeSegment.selectedSegmentIndex = LSMapPickerCoordinateModeRoute;
    self.mapHintLabel.text = @"";

    self.selectedCoordinate = simulator.currentCoordinate;
    [self syncFieldsFromCoordinate];

    switch (simulator.transportMode) {
        case LSTransportModeWalking: self.transportModeSegment.selectedSegmentIndex = 0; break;
        case LSTransportModeCycling: self.transportModeSegment.selectedSegmentIndex = 1; break;
        case LSTransportModeDriving: self.transportModeSegment.selectedSegmentIndex = 2; break;
        case LSTransportModeCustom: self.transportModeSegment.selectedSegmentIndex = 3; break;
    }

    [self ls_updateRouteWaypointLabels];
    [self ls_updateRoutePlaybackCell];
    [self refreshStatusPill];
    [self.tableView reloadData];
}

#pragma mark - Table View Data Source for Route Mode

- (NSInteger)ls_routeNumberOfSections {
    BOOL hasRouteOrSim = self.fetchedRoute != nil || [[LSRouteSimulator shared] isSimulating];
    return hasRouteOrSim ? 4 : 2;
}

- (NSInteger)ls_routeNumberOfRowsInSection:(NSInteger)section {
    BOOL hasRouteOrSim = self.fetchedRoute != nil || [[LSRouteSimulator shared] isSimulating];

    if (section == 0) {
        return 2; // Start Point, Destination
    }

    if (section == 1) {
        return 1; // Get Route Directions button
    }

    if (hasRouteOrSim) {
        if (section == 2) {
            return (self.transportModeSegment.selectedSegmentIndex == 3) ? 2 : 1;
        }
        if (section == 3) {
            return 1; // Playback controls
        }
    }
    return 0;
}

- (nullable NSString *)ls_routeTitleForHeaderInSection:(NSInteger)section {
    BOOL hasRouteOrSim = self.fetchedRoute != nil || [[LSRouteSimulator shared] isSimulating];

    if (section == 0) return @"Route Waypoints";
    if (hasRouteOrSim) {
        if (section == 2) return @"Transport & Speed";
        if (section == 3) return @"Playback Controls";
    }
    return nil;
}

- (UITableViewCell *)ls_routeCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL hasRouteOrSim = self.fetchedRoute != nil || [[LSRouteSimulator shared] isSimulating];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) return self.routeStartCell;
        return self.routeDestCell;
    }

    if (indexPath.section == 1) {
        return self.routeGetDirectionsCell;
    }

    if (hasRouteOrSim) {
        if (indexPath.section == 2) {
            if (indexPath.row == 0) return self.routeTransportCell;
            return self.routeCustomSpeedCell;
        }

        if (indexPath.section == 3) {
            [self ls_updateRoutePlaybackCell];
            return self.routePlaybackCell;
        }
    }

    return [[UITableViewCell alloc] init];
}

- (void)ls_routeDidSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
        if (indexPath.row == 0) {
            [self handleSearchStartTapped];
        } else if (indexPath.row == 1) {
            [self handleSearchDestinationTapped];
        }
    }
}

#pragma mark - Route Waypoint Search

- (void)handleSearchStartTapped {
    [self presentRouteWaypointSearchAlertForTarget:LSRouteWaypointTargetStart];
}

- (void)handleSearchDestinationTapped {
    [self presentRouteWaypointSearchAlertForTarget:LSRouteWaypointTargetDestination];
}

- (void)presentRouteWaypointSearchAlertForTarget:(LSRouteWaypointTarget)target {
    BOOL isStart = (target == LSRouteWaypointTargetStart);
    NSString *title = isStart ? @"Search Start Point" : @"Search Destination";
    NSString *message = @"Enter an address, city, landmark, or coordinates:";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];

    __weak typeof(self) weakSelf = self;
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = isStart ? @"e.g. Times Square or lat, lon" : @"e.g. Central Park or lat, lon";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
        textField.returnKeyType = UIReturnKeySearch;
        NSString *existing = isStart ? weakSelf.startWaypointName : weakSelf.destinationWaypointName;
        if (existing.length > 0) {
            textField.text = existing;
        }
    }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    UIAlertAction *searchAction = [UIAlertAction actionWithTitle:@"Search"
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull action) {
        (void)action;
        UITextField *field = alert.textFields.firstObject;
        NSString *query = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (query.length > 0) {
            [weakSelf executeRouteWaypointSearch:query forTarget:target];
        }
    }];

    [alert addAction:cancelAction];
    [alert addAction:searchAction];
    alert.preferredAction = searchAction;

    [self presentViewController:alert animated:YES completion:nil];
}

- (void)executeRouteWaypointSearch:(NSString *)query forTarget:(LSRouteWaypointTarget)target {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;

    // Check for direct coordinate input: "37.7749, -122.4194"
    NSArray<NSString *> *parts = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length > 0) [tokens addObject:p];
    }
    if (tokens.count == 2) {
        double lat = [tokens[0] doubleValue];
        double lon = [tokens[1] doubleValue];
        if (CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(lat, lon)) &&
            fabs(lat) <= 90.0 && fabs(lon) <= 180.0 &&
            (fabs(lat) > 0.0001 || fabs(lon) > 0.0001)) {
            [self applyRouteWaypointCoordinate:CLLocationCoordinate2DMake(lat, lon)
                                          name:[NSString stringWithFormat:@"%.5f, %.5f", lat, lon]
                                     forTarget:target];
            return;
        }
    }

    [self.routeSpinner startAnimating];
    self.statusLabel.text = [NSString stringWithFormat:@"Searching %@...", (target == LSRouteWaypointTargetStart ? @"start" : @"destination")];

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = trimmed;
    if (CLLocationCoordinate2DIsValid(self.mapView.region.center)) {
        request.region = self.mapView.region;
    }

    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf.routeSpinner stopAnimating];
            [strongSelf refreshStatusPill];

            if (error || !response || response.mapItems.count == 0) {
                [strongSelf playRouteFailureHaptic];
                UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:@"Location Not Found"
                                                                                  message:[NSString stringWithFormat:@"No matching places found for \"%@\".", trimmed]
                                                                           preferredStyle:UIAlertControllerStyleAlert];
                [errAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
                [strongSelf presentViewController:errAlert animated:YES completion:nil];
                return;
            }

            if (response.mapItems.count == 1) {
                MKMapItem *item = response.mapItems.firstObject;
                NSString *name = item.name ?: trimmed;
                [strongSelf applyRouteWaypointCoordinate:item.placemark.coordinate name:name forTarget:target];
            } else {
                UIAlertController *chooser = [UIAlertController alertControllerWithTitle:@"Select Location"
                                                                                 message:[NSString stringWithFormat:@"Found multiple matches for \"%@\":", trimmed]
                                                                          preferredStyle:UIAlertControllerStyleActionSheet];
                NSUInteger limit = MIN(response.mapItems.count, 4);
                for (NSUInteger i = 0; i < limit; i++) {
                    MKMapItem *item = response.mapItems[i];
                    NSString *itemTitle = item.name ?: @"Unknown";
                    if (item.placemark.title && ![item.placemark.title isEqualToString:itemTitle]) {
                        itemTitle = [NSString stringWithFormat:@"%@ (%@)", itemTitle, item.placemark.title];
                    }
                    [chooser addAction:[UIAlertAction actionWithTitle:itemTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                        (void)action;
                        [strongSelf applyRouteWaypointCoordinate:item.placemark.coordinate name:item.name ?: trimmed forTarget:target];
                    }]];
                }
                [chooser addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
                if (chooser.popoverPresentationController) {
                    UIView *sourceView = (target == LSRouteWaypointTargetStart) ? strongSelf.searchStartButton : strongSelf.searchDestButton;
                    chooser.popoverPresentationController.sourceView = sourceView ?: strongSelf.view;
                    chooser.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : strongSelf.view.bounds;
                }
                [strongSelf presentViewController:chooser animated:YES completion:nil];
            }
        });
    }];
}

- (void)applyRouteWaypointCoordinate:(CLLocationCoordinate2D)coord name:(nullable NSString *)name forTarget:(LSRouteWaypointTarget)target {
    if (!CLLocationCoordinate2DIsValid(coord)) return;

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback impactOccurred];

    if (target == LSRouteWaypointTargetStart) {
        self.startWaypointName = name;
        if (!self.startAnnotation) {
            self.startAnnotation = [[LSStartAnnotation alloc] init];
            self.startAnnotation.title = @"Start";
            [self.mapView addAnnotation:self.startAnnotation];
        }
        self.startAnnotation.coordinate = coord;
        self.routePlacementPhase = self.destinationAnnotation ? LSRoutePlacementPhaseStart : LSRoutePlacementPhaseDestination;
        self.mapHintLabel.text = self.destinationAnnotation ? @"  Tap Get Route Directions  " : @"  Tap map for destination  ";
    } else {
        self.destinationWaypointName = name;
        if (!self.destinationAnnotation) {
            self.destinationAnnotation = [[LSDestinationAnnotation alloc] init];
            self.destinationAnnotation.title = @"Destination";
            [self.mapView addAnnotation:self.destinationAnnotation];
        }
        self.destinationAnnotation.coordinate = coord;
        self.routePlacementPhase = LSRoutePlacementPhaseStart;
        self.mapHintLabel.text = self.startAnnotation ? @"  Tap Get Route Directions  " : @"  Tap map for start point  ";
    }

    self.fetchedRoute = nil;
    if (self.routePolyline) {
        [self.mapView removeOverlay:self.routePolyline];
        self.routePolyline = nil;
    }

    [self ls_updateRouteWaypointLabels];
    [self ls_updateRoutePlaybackCell];
    [self.tableView reloadData];

    if (self.startAnnotation && CLLocationCoordinate2DIsValid(self.startAnnotation.coordinate) &&
        self.destinationAnnotation && CLLocationCoordinate2DIsValid(self.destinationAnnotation.coordinate)) {
        [self handleGetRouteTapped];
    } else {
        [self.mapView setCenterCoordinate:coord animated:YES];
    }
}

#pragma mark - LSRouteSimulatorDelegate

- (void)routeSimulator:(LSRouteSimulator *)simulator didUpdateCoordinate:(CLLocationCoordinate2D)coordinate heading:(CLLocationDirection)heading {
    (void)heading;
    double kmh = [LSRouteSimulator speedMetersPerSecondForMode:simulator.transportMode customSpeedKmh:simulator.customSpeedKmh] * 3.6;
    self.statusLabel.text = [NSString stringWithFormat:@"Simulating · %.1f km/h", kmh];
    self.statusDot.backgroundColor = UIColor.systemGreenColor;

    self.selectedCoordinate = coordinate;
    self.startAnnotation.coordinate = coordinate;
    self.pinAnnotation.coordinate = coordinate;
    self.suppressFieldSync = YES;
    self.latitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.latitude];
    self.longitudeField.text = [NSString stringWithFormat:@"%.6f", coordinate.longitude];
    self.suppressFieldSync = NO;
    [self ls_updateRouteWaypointLabels];
}

- (void)routeSimulatorDidFinish:(LSRouteSimulator *)simulator {
    (void)simulator;
    [PersistenceManager shared].simulationWasActive = NO;

    CLLocationCoordinate2D finalCoord = kCLLocationCoordinate2DInvalid;
    if (self.routePolyline && self.routePolyline.pointCount > 0) {
        [self.routePolyline getCoordinates:&finalCoord range:NSMakeRange(self.routePolyline.pointCount - 1, 1)];
    }
    if (CLLocationCoordinate2DIsValid(finalCoord)) {
        PersistenceManager *store = [PersistenceManager shared];
        if ([store setSpoofCoordinate:finalCoord enabled:YES]) {
            self.selectedCoordinate = finalCoord;
            [self syncFieldsFromCoordinate];
        } else {
            [self playRouteFailureHaptic];
            self.statusLabel.text = @"Route complete (spoof rejected)";
        }
    }

    self.statusLabel.text = @"Route complete";
    [self ls_updateRoutePlaybackCell];
    [self refreshStatusPill];
    [self.tableView reloadData];
}

#pragma mark - Map Overlay & Annotation Views

- (MKOverlayRenderer *)ls_rendererForMapOverlay:(id<MKOverlay>)overlay {
    if (overlay == self.driftCircleOverlay) {
        MKCircleRenderer *renderer = [[MKCircleRenderer alloc] initWithCircle:(MKCircle *)overlay];
        renderer.fillColor = [UIColor.systemPurpleColor colorWithAlphaComponent:0.18];
        renderer.strokeColor = [UIColor.systemPurpleColor colorWithAlphaComponent:0.65];
        renderer.lineWidth = 1.5;
        renderer.lineDashPattern = @[@4, @4];
        return renderer;
    }
    if (overlay == self.routePolyline) {
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:(MKPolyline *)overlay];
        renderer.strokeColor = UIColor.systemBlueColor;
        renderer.lineWidth = 4.0;
        return renderer;
    }
    return nil;
}

- (nullable MKAnnotationView *)ls_viewForRouteAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[LSStartAnnotation class]]) {
        static NSString * const identifier = @"LSStartPin";
        MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[self.mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        if (!view) {
            view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
            view.canShowCallout = YES;
            view.draggable = YES;
            view.glyphImage = [MapPickerViewController systemImageNamedWithFallback:@"flag.fill" configuration:nil];
        } else {
            view.annotation = annotation;
        }
        view.markerTintColor = UIColor.systemGreenColor;
        return view;
    }

    if ([annotation isKindOfClass:[LSDestinationAnnotation class]]) {
        static NSString * const identifier = @"LSDestinationPin";
        MKMarkerAnnotationView *view = (MKMarkerAnnotationView *)[self.mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        if (!view) {
            view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
            view.canShowCallout = YES;
            view.draggable = YES;
            view.glyphImage = [MapPickerViewController systemImageNamedWithFallback:@"flag.checkered" configuration:nil];
        } else {
            view.annotation = annotation;
        }
        view.markerTintColor = UIColor.systemRedColor;
        return view;
    }

    return nil;
}

- (void)ls_routeAnnotationDragEnded:(MKAnnotationView *)view {
    if (view.annotation == self.startAnnotation) {
        self.startWaypointName = nil;
    }
    if (view.annotation == self.destinationAnnotation) {
        self.destinationWaypointName = nil;
    }
    if (view.annotation == self.startAnnotation || view.annotation == self.destinationAnnotation) {
        self.fetchedRoute = nil;
        if (self.routePolyline) {
            [self.mapView removeOverlay:self.routePolyline];
            self.routePolyline = nil;
        }
        [self ls_updateRouteWaypointLabels];
        [self ls_updateRoutePlaybackCell];
        [self.tableView reloadData];
    }
}

@end
