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
    UIImage *routeIcon = [UIImage systemImageNamed:@"arrow.triangle.turn.up.right.diamond.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIFontWeightBold]];
    [self.getRouteButton setImage:routeIcon forState:UIControlStateNormal];
    self.getRouteButton.tintColor = UIColor.whiteColor;
    self.getRouteButton.backgroundColor = UIColor.systemBlueColor;
    self.getRouteButton.layer.cornerRadius = 14.0;
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
    self.customSpeedField.placeholder = @"30 km/h";
    self.customSpeedField.keyboardType = UIKeyboardTypeDecimalPad;
    self.customSpeedField.text = @"30";
    self.customSpeedField.textAlignment = NSTextAlignmentRight;
    self.customSpeedField.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightRegular];
    self.customSpeedField.textColor = UIColor.labelColor;
    [self.customSpeedField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];

    // Play Route Button
    self.playRouteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playRouteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.playRouteButton setTitle:@"  Start Simulation" forState:UIControlStateNormal];
    [self.playRouteButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.playRouteButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    UIImage *playIcon = [UIImage systemImageNamed:@"play.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIFontWeightBold]];
    [self.playRouteButton setImage:playIcon forState:UIControlStateNormal];
    self.playRouteButton.tintColor = UIColor.whiteColor;
    self.playRouteButton.backgroundColor = UIColor.systemGreenColor;
    self.playRouteButton.layer.cornerRadius = 14.0;
    self.playRouteButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.playRouteButton addTarget:self action:@selector(handlePlayRouteTapped) forControlEvents:UIControlEventTouchUpInside];

    // Pause Route Button
    self.pauseRouteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.pauseRouteButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.pauseRouteButton setTitle:@"  Pause" forState:UIControlStateNormal];
    [self.pauseRouteButton setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    self.pauseRouteButton.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    UIImage *pauseIcon = [UIImage systemImageNamed:@"pause.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIFontWeightSemibold]];
    [self.pauseRouteButton setImage:pauseIcon forState:UIControlStateNormal];
    self.pauseRouteButton.tintColor = UIColor.labelColor;
    self.pauseRouteButton.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.pauseRouteButton.layer.cornerRadius = 14.0;
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
    UIImage *stopIcon = [UIImage systemImageNamed:@"stop.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15.0 weight:UIFontWeightSemibold]];
    [self.stopRouteButton setImage:stopIcon forState:UIControlStateNormal];
    self.stopRouteButton.tintColor = UIColor.systemRedColor;
    self.stopRouteButton.backgroundColor = [UIColor.systemRedColor colorWithAlphaComponent:0.12];
    self.stopRouteButton.layer.cornerRadius = 14.0;
    self.stopRouteButton.layer.cornerCurve = kCACornerCurveContinuous;
    self.stopRouteButton.layer.borderWidth = 1.0;
    self.stopRouteButton.layer.borderColor = [UIColor.systemRedColor colorWithAlphaComponent:0.4].CGColor;
    [self.stopRouteButton addTarget:self action:@selector(handleStopRouteTapped) forControlEvents:UIControlEventTouchUpInside];
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

    [self refreshStatusPill];
    [self.tableView reloadData];
}

- (void)ls_clearRouteAnnotationsAndOverlay {
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
        self.routePlacementPhase = LSRoutePlacementPhaseDestination;
        self.mapHintLabel.text = @"  Tap map for destination  ";
    } else {
        if (!self.destinationAnnotation) {
            self.destinationAnnotation = [[LSDestinationAnnotation alloc] init];
            self.destinationAnnotation.title = @"Destination";
            [self.mapView addAnnotation:self.destinationAnnotation];
        }
        self.destinationAnnotation.coordinate = coordinate;
        self.routePlacementPhase = LSRoutePlacementPhaseStart;
        self.mapHintLabel.text = @"  Tap map to move start  ";
    }

    self.fetchedRoute = nil;
    if (self.routePolyline) {
        [self.mapView removeOverlay:self.routePolyline];
        self.routePolyline = nil;
    }

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
            [strongSelf.tableView reloadData];
            [strongSelf refreshStatusPill];
        });
    }];
}

- (void)handleTransportModeChanged:(UISegmentedControl *)sender {
    (void)sender;
    LSRouteSimulator *simulator = [LSRouteSimulator shared];
    if (simulator.isSimulating) {
        simulator.transportMode = [self ls_selectedTransportMode];
        if (simulator.transportMode == LSTransportModeCustom) {
            NSNumber *parsed = [self ls_parsedCoordinateComponentFromText:self.customSpeedField.text];
            simulator.customSpeedKmh = parsed ? parsed.doubleValue : 30.0;
        }
    }
    [self.tableView reloadData];
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

    [self refreshStatusPill];
    [self.tableView reloadData];
}

#pragma mark - Table View Data Source for Route Mode

- (NSInteger)ls_routeNumberOfSections {
    BOOL hasRouteOrSim = self.fetchedRoute != nil || [[LSRouteSimulator shared] isSimulating];
    // Section 0: Route Waypoints (Start, Dest, Get Route)
    // Section 1 (if route): Speed & Transport Mode
    // Section 2 (if route): Simulation Controls
    // Section 3: Cancel Action
    return hasRouteOrSim ? 4 : 2;
}

- (NSInteger)ls_routeNumberOfRowsInSection:(NSInteger)section {
    BOOL hasRouteOrSim = self.fetchedRoute != nil || [[LSRouteSimulator shared] isSimulating];

    if (section == 0) {
        return 3; // Start Point, Destination, Get Route Button
    }

    if (hasRouteOrSim) {
        if (section == 1) {
            return (self.transportModeSegment.selectedSegmentIndex == 3) ? 2 : 1; // Transport segment, (Custom speed)
        }
        if (section == 2) {
            return 1; // Play or Pause/Stop row
        }
        if (section == 3) {
            return 1; // Cancel button
        }
    } else {
        if (section == 1) {
            return 1; // Cancel button
        }
    }
    return 0;
}

- (nullable NSString *)ls_routeTitleForHeaderInSection:(NSInteger)section {
    BOOL hasRouteOrSim = self.fetchedRoute != nil || [[LSRouteSimulator shared] isSimulating];

    if (section == 0) return @"Route Waypoints";
    if (hasRouteOrSim) {
        if (section == 1) return @"Transport & Speed";
        if (section == 2) return @"Playback Controls";
    }
    return nil;
}

- (UITableViewCell *)ls_routeCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BOOL hasRouteOrSim = self.fetchedRoute != nil || [[LSRouteSimulator shared] isSimulating];

    if (indexPath.section == 0) {
        if (indexPath.row == 0 || indexPath.row == 1) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
            cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            BOOL isStart = (indexPath.row == 0);
            UIView *badge = isStart ?
                [MapPickerViewController iconBadgeWithSymbolName:@"flag.fill" backgroundColor:UIColor.systemGreenColor] :
                [MapPickerViewController iconBadgeWithSymbolName:@"flag.checkered" backgroundColor:UIColor.systemRedColor];
            badge.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:badge];

            UILabel *lbl = [[UILabel alloc] init];
            lbl.translatesAutoresizingMaskIntoConstraints = NO;
            lbl.text = isStart ? @"Start Point" : @"Destination";
            lbl.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
            lbl.textColor = UIColor.labelColor;
            [cell.contentView addSubview:lbl];

            UILabel *sub = [[UILabel alloc] init];
            sub.translatesAutoresizingMaskIntoConstraints = NO;
            sub.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
            sub.textColor = UIColor.secondaryLabelColor;

            CLLocationCoordinate2D coord = isStart ?
                (self.startAnnotation ? self.startAnnotation.coordinate : kCLLocationCoordinate2DInvalid) :
                (self.destinationAnnotation ? self.destinationAnnotation.coordinate : kCLLocationCoordinate2DInvalid);

            if (CLLocationCoordinate2DIsValid(coord)) {
                sub.text = [NSString stringWithFormat:@"%.5f, %.5f", coord.latitude, coord.longitude];
            } else {
                sub.text = isStart ? @"Tap map to set start position" : @"Tap map to set destination";
            }
            [cell.contentView addSubview:sub];

            [NSLayoutConstraint activateConstraints:@[
                [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
                [lbl.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10.0],

                [sub.leadingAnchor constraintEqualToAnchor:lbl.leadingAnchor],
                [sub.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:3.0],
                [sub.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10.0],
                [sub.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0]
            ]];
            return cell;
        } else {
            // Get Route button cell
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = UIColor.clearColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            [self.getRouteButton removeFromSuperview];
            [cell.contentView addSubview:self.getRouteButton];
            [NSLayoutConstraint activateConstraints:@[
                [self.getRouteButton.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [self.getRouteButton.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [self.getRouteButton.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
                [self.getRouteButton.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0],
                [self.getRouteButton.heightAnchor constraintEqualToConstant:48.0]
            ]];
            return cell;
        }
    }

    if (hasRouteOrSim) {
        if (indexPath.section == 1) {
            if (indexPath.row == 0) {
                UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
                cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;

                [self.transportModeSegment removeFromSuperview];
                [cell.contentView addSubview:self.transportModeSegment];
                [NSLayoutConstraint activateConstraints:@[
                    [self.transportModeSegment.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                    [self.transportModeSegment.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                    [self.transportModeSegment.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8.0],
                    [self.transportModeSegment.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8.0],
                    [self.transportModeSegment.heightAnchor constraintEqualToConstant:32.0]
                ]];
                return cell;
            } else {
                // Custom speed row
                UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
                cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
                cell.selectionStyle = UITableViewCellSelectionStyleNone;

                UIView *badge = [MapPickerViewController iconBadgeWithSymbolName:@"speedometer" backgroundColor:UIColor.systemOrangeColor];
                badge.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:badge];

                UILabel *lbl = [[UILabel alloc] init];
                lbl.translatesAutoresizingMaskIntoConstraints = NO;
                lbl.text = @"Speed (km/h)";
                lbl.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightRegular];
                lbl.textColor = UIColor.labelColor;
                [cell.contentView addSubview:lbl];

                [self.customSpeedField removeFromSuperview];
                [cell.contentView addSubview:self.customSpeedField];

                [NSLayoutConstraint activateConstraints:@[
                    [badge.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16.0],
                    [badge.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                    [lbl.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12.0],
                    [lbl.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

                    [self.customSpeedField.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16.0],
                    [self.customSpeedField.leadingAnchor constraintEqualToAnchor:lbl.trailingAnchor constant:8.0],
                    [self.customSpeedField.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                    [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:46.0]
                ]];
                return cell;
            }
        }

        if (indexPath.section == 2) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = UIColor.clearColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            LSRouteSimulator *simulator = [LSRouteSimulator shared];
            if (!simulator.isSimulating) {
                [self.playRouteButton removeFromSuperview];
                [cell.contentView addSubview:self.playRouteButton];
                [NSLayoutConstraint activateConstraints:@[
                    [self.playRouteButton.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                    [self.playRouteButton.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                    [self.playRouteButton.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
                    [self.playRouteButton.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0],
                    [self.playRouteButton.heightAnchor constraintEqualToConstant:48.0]
                ]];
            } else {
                UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.pauseRouteButton, self.stopRouteButton]];
                stack.translatesAutoresizingMaskIntoConstraints = NO;
                stack.axis = UILayoutConstraintAxisHorizontal;
                stack.spacing = 12.0;
                stack.distribution = UIStackViewDistributionFillEqually;
                [cell.contentView addSubview:stack];

                [NSLayoutConstraint activateConstraints:@[
                    [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                    [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                    [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
                    [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0],
                    [stack.heightAnchor constraintEqualToConstant:48.0]
                ]];
            }
            return cell;
        }

        if (indexPath.section == 3) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = UIColor.clearColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            [self.cancelButton removeFromSuperview];
            [cell.contentView addSubview:self.cancelButton];
            [NSLayoutConstraint activateConstraints:@[
                [self.cancelButton.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [self.cancelButton.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [self.cancelButton.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
                [self.cancelButton.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0],
                [self.cancelButton.heightAnchor constraintEqualToConstant:48.0]
            ]];
            return cell;
        }
    } else {
        if (indexPath.section == 1) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
            cell.backgroundColor = UIColor.clearColor;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;

            [self.cancelButton removeFromSuperview];
            [cell.contentView addSubview:self.cancelButton];
            [NSLayoutConstraint activateConstraints:@[
                [self.cancelButton.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
                [self.cancelButton.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
                [self.cancelButton.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4.0],
                [self.cancelButton.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4.0],
                [self.cancelButton.heightAnchor constraintEqualToConstant:48.0]
            ]];
            return cell;
        }
    }

    return [[UITableViewCell alloc] init];
}

- (void)ls_routeDidSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)indexPath;
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
    [self refreshStatusPill];
    [self.tableView reloadData];
}

#pragma mark - Map Overlay & Annotation Views

- (MKOverlayRenderer *)ls_rendererForMapOverlay:(id<MKOverlay>)overlay {
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
        } else {
            view.annotation = annotation;
        }
        view.markerTintColor = UIColor.systemRedColor;
        return view;
    }

    return nil;
}

- (void)ls_routeAnnotationDragEnded:(MKAnnotationView *)view {
    if (view.annotation == self.startAnnotation || view.annotation == self.destinationAnnotation) {
        self.fetchedRoute = nil;
        if (self.routePolyline) {
            [self.mapView removeOverlay:self.routePolyline];
            self.routePolyline = nil;
        }
        [self.tableView reloadData];
    }
}

@end
