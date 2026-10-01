#import "MapPickerViewController+Private.h"
#import "LocationSpoofer.h"
#import "BookmarksManager.h"
#import "PersistenceManager.h"

static NSString * const kLSBookmarksCell = @"LSBookmarksCell";

typedef NS_ENUM(NSInteger, LSBookmarksSection) {
    LSBookmarksSectionSaved = 0,
    LSBookmarksSectionRecents = 1
};

@implementation MapPickerViewController (LSBookmarksUI)

- (void)buildBookmarksPanel {
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kLSBookmarksCell];
}

- (void)updatePanelTabVisibility {
    BOOL mapTab = (self.panelTab == LSMapPickerPanelTabMap);

    if (mapTab) {
        self.searchBar.hidden = NO;
        self.coordinateModeSegment.hidden = NO;
    }

    [UIView animateWithDuration:0.25 animations:^{
        if (mapTab) {
            self.searchBarHeightConstraint.constant = 48.0;
            self.searchBarBottomConstraint.constant = 6.0;
            self.coordinateModeHeightConstraint.constant = 32.0;
            self.coordinateModeBottomConstraint.constant = -8.0;
            self.searchBar.alpha = 1.0;
            self.coordinateModeSegment.alpha = 1.0;
        } else {
            self.searchBarHeightConstraint.constant = 0.0;
            self.searchBarBottomConstraint.constant = 0.0;
            self.coordinateModeHeightConstraint.constant = 0.0;
            self.coordinateModeBottomConstraint.constant = 0.0;
            self.searchBar.alpha = 0.0;
            self.coordinateModeSegment.alpha = 0.0;
        }
        [self ls_updateTableHeaderLayout];
    } completion:^(BOOL finished) {
        (void)finished;
        self.searchBar.hidden = !mapTab;
        self.coordinateModeSegment.hidden = !mapTab;
        [self ls_updateTableHeaderLayout];
    }];

    if (mapTab) {
        [self updateCoordinateModeVisibility];
    } else {
        [self.tableView reloadData];
    }
}

- (void)handlePanelTabChanged:(UISegmentedControl *)sender {
    self.panelTab = (LSMapPickerPanelTab)sender.selectedSegmentIndex;
    [self updatePanelTabVisibility];
}

- (void)handleCoordinateModeChanged:(UISegmentedControl *)sender {
    self.coordinateMode = (LSMapPickerCoordinateMode)sender.selectedSegmentIndex;
    [self updateCoordinateModeVisibility];
}

- (void)handleBookmarkSaveTapped {
    [self presentSaveBookmarkAlertWithSuggestedName:nil coordinate:self.selectedCoordinate];
}

- (void)presentSaveBookmarkAlertWithSuggestedName:(nullable NSString *)name coordinate:(CLLocationCoordinate2D)coordinate {
    NSString *suggested = name.length > 0 ? name : @"Location";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save Bookmark"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = suggested;
        textField.placeholder = @"Name";
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSString *bookmarkName = alert.textFields.firstObject.text;
        if (bookmarkName.length == 0) {
            bookmarkName = @"Location";
        }
        [[BookmarksManager shared] addBookmarkWithName:bookmarkName coordinate:coordinate];
        [strongSelf playBookmarkSavedHaptic];
        [strongSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];

    if (name.length == 0) {
        CLLocation *location = [[CLLocation alloc] initWithLatitude:coordinate.latitude
                                                           longitude:coordinate.longitude];
        CLGeocoder *geocoder = [[CLGeocoder alloc] init];
        [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!error && placemarks.firstObject.name.length > 0) {
                    UITextField *field = alert.textFields.firstObject;
                    if ([field.text isEqualToString:@"Location"]) {
                        field.text = placemarks.firstObject.name;
                    }
                }
            });
        }];
    }
}

- (NSInteger)ls_bookmarksNumberOfSections {
    return 2;
}

- (NSInteger)ls_bookmarksNumberOfRowsInSection:(NSInteger)section {
    if (section == LSBookmarksSectionSaved) {
        return (NSInteger)[BookmarksManager shared].allBookmarks.count;
    }
    return (NSInteger)[PersistenceManager shared].recentLocations.count;
}

- (nullable NSString *)ls_bookmarksTitleForHeaderInSection:(NSInteger)section {
    if (section == LSBookmarksSectionSaved) {
        return @"Saved Bookmarks";
    }
    return @"Recent Locations";
}

- (nullable UIView *)ls_bookmarksHeaderForSection:(NSInteger)section {
    if (section != LSBookmarksSectionSaved) {
        return nil;
    }

    UIView *header = [[UIView alloc] init];
    header.backgroundColor = UIColor.clearColor;

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Saved Bookmarks";
    title.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    title.textColor = UIColor.secondaryLabelColor;
    [header addSubview:title];

    UIButton *editButton = [UIButton buttonWithType:UIButtonTypeSystem];
    editButton.translatesAutoresizingMaskIntoConstraints = NO;
    [editButton setTitle:self.bookmarksEditMode ? @"Done" : @"Edit" forState:UIControlStateNormal];
    editButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    [editButton addTarget:self action:@selector(ls_toggleBookmarksEditMode) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:editButton];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
        [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [editButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
        [editButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [header.heightAnchor constraintEqualToConstant:32.0]
    ]];
    return header;
}

- (UITableViewCell *)ls_bookmarksCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kLSBookmarksCell];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kLSBookmarksCell];
    }
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

    CLLocationCoordinate2D coordinate = kCLLocationCoordinate2DInvalid;
    NSString *title = @"Location";

    if (indexPath.section == LSBookmarksSectionRecents) {
        NSArray<NSDictionary *> *recents = [PersistenceManager shared].recentLocations;
        if (indexPath.row < (NSInteger)recents.count) {
            NSDictionary *entry = recents[indexPath.row];
            coordinate = CLLocationCoordinate2DMake([entry[@"LSRecentLat"] doubleValue], [entry[@"LSRecentLon"] doubleValue]);
            title = entry[@"LSRecentName"];
            if (title.length == 0 || [title isEqualToString:@"Location"] || [title isEqualToString:@"Resolving address..."]) {
                CLLocation *loc = [[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
                CLGeocoder *geocoder = [[CLGeocoder alloc] init];
                __weak typeof(self) weakSelf = self;
                [geocoder reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
                    if (!error && placemarks.count > 0) {
                        CLPlacemark *pm = placemarks.firstObject;
                        NSString *resolved = nil;
                        if (pm.areasOfInterest.firstObject.length > 0) {
                            resolved = pm.areasOfInterest.firstObject;
                        } else if (pm.name.length > 0 && pm.thoroughfare.length > 0 && ![pm.name isEqualToString:pm.thoroughfare]) {
                            resolved = pm.name;
                        } else if (pm.thoroughfare.length > 0) {
                            resolved = pm.locality ? [NSString stringWithFormat:@"%@, %@", pm.thoroughfare, pm.locality] : pm.thoroughfare;
                        } else if (pm.name.length > 0) {
                            resolved = pm.name;
                        }
                        if (resolved.length > 0) {
                            [[PersistenceManager shared] updateRecentCoordinateName:resolved forCoordinate:coordinate];
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [weakSelf.tableView reloadData];
                            });
                        }
                    }
                }];
                title = [NSString stringWithFormat:@"%.4f, %.4f", coordinate.latitude, coordinate.longitude];
            }
        }

        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = title;
        content.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        content.textProperties.color = UIColor.labelColor;
        if (CLLocationCoordinate2DIsValid(coordinate)) {
            content.secondaryText = [NSString stringWithFormat:@"%.5f, %.5f", coordinate.latitude, coordinate.longitude];
        }
        content.secondaryTextProperties.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
        content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
        content.image = [MapPickerViewController systemImageNamedWithFallback:@"clock.fill" configuration:nil];
        content.imageProperties.tintColor = UIColor.systemBlueColor;
        cell.contentConfiguration = content;
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;

        if (indexPath.row < (NSInteger)bookmarks.count) {
            LSBookmark *bookmark = bookmarks[indexPath.row];
            coordinate = bookmark.coordinate;
            title = bookmark.name;
        }

        UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
        content.text = title;
        content.textProperties.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        content.textProperties.color = UIColor.labelColor;
        if (CLLocationCoordinate2DIsValid(coordinate)) {
            content.secondaryText = [NSString stringWithFormat:@"%.5f, %.5f", coordinate.latitude, coordinate.longitude];
        }
        content.secondaryTextProperties.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightRegular];
        content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
        content.image = [MapPickerViewController systemImageNamedWithFallback:@"bookmark.fill" configuration:nil];
        content.imageProperties.tintColor = UIColor.systemYellowColor;
        cell.contentConfiguration = content;

        UIButton *applyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        applyBtn.frame = CGRectMake(0, 0, 68, 30);
        [applyBtn setTitle:@"Apply" forState:UIControlStateNormal];
        [applyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        applyBtn.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
        applyBtn.backgroundColor = UIColor.systemBlueColor;
        applyBtn.layer.cornerRadius = 15.0;
        applyBtn.layer.cornerCurve = kCACornerCurveContinuous;
        [applyBtn addTarget:self action:@selector(ls_applyBookmarkFromButton:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = applyBtn;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

- (void)ls_bookmarksDidSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.tableView.isEditing) {
        return;
    }

    CLLocationCoordinate2D coordinate = kCLLocationCoordinate2DInvalid;

    if (indexPath.section == LSBookmarksSectionRecents) {
        NSArray<NSDictionary *> *recents = [PersistenceManager shared].recentLocations;
        if (indexPath.row < (NSInteger)recents.count) {
            NSDictionary *entry = recents[indexPath.row];
            coordinate = CLLocationCoordinate2DMake([entry[@"LSRecentLat"] doubleValue], [entry[@"LSRecentLon"] doubleValue]);
        }
    } else {
        NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
        if (indexPath.row < (NSInteger)bookmarks.count) {
            coordinate = bookmarks[indexPath.row].coordinate;
        }
    }

    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        return;
    }

    // Switch back to Map tab and center pin at chosen coordinate
    self.panelTab = LSMapPickerPanelTabMap;
    self.panelTabSegment.selectedSegmentIndex = LSMapPickerPanelTabMap;
    [self updatePanelTabVisibility];
    [self movePinToCoordinate:coordinate animated:YES];
}

- (BOOL)ls_bookmarksCanEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == LSBookmarksSectionSaved;
}

- (void)ls_bookmarksCommitDeleteAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
    NSString *name = (indexPath.row < (NSInteger)bookmarks.count) ? bookmarks[indexPath.row].name : @"this bookmark";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Delete Bookmark"
                                                                   message:[NSString stringWithFormat:@"Delete \"%@\"?", name]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [[BookmarksManager shared] removeBookmarkAtIndex:(NSUInteger)indexPath.row];
        [strongSelf.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)ls_bookmarksCanMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == LSBookmarksSectionSaved && self.bookmarksEditMode;
}

- (void)ls_bookmarksMoveFromIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    [[BookmarksManager shared] moveBookmarkFromIndex:(NSUInteger)source.row toIndex:(NSUInteger)destination.row];
}

- (void)ls_toggleBookmarksEditMode {
    self.bookmarksEditMode = !self.bookmarksEditMode;
    [self.tableView setEditing:self.bookmarksEditMode animated:YES];

    UIView *header = [self.tableView headerViewForSection:LSBookmarksSectionSaved];
    for (UIView *sub in header.subviews) {
        if ([sub isKindOfClass:[UIButton class]]) {
            [(UIButton *)sub setTitle:(self.bookmarksEditMode ? @"Done" : @"Edit") forState:UIControlStateNormal];
        }
    }
}

- (void)ls_applyBookmarkFromButton:(UIButton *)sender {
    CGPoint buttonPosition = [sender convertPoint:CGPointZero toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:buttonPosition];
    if (!indexPath || indexPath.section != LSBookmarksSectionSaved) {
        return;
    }

    NSArray<LSBookmark *> *bookmarks = [BookmarksManager shared].allBookmarks;
    if (indexPath.row >= (NSInteger)bookmarks.count) {
        return;
    }

    LSBookmark *bookmark = bookmarks[indexPath.row];
    PersistenceManager *store = [PersistenceManager shared];
    if (![store setSpoofCoordinate:bookmark.coordinate enabled:YES]) {
        [self playRouteFailureHaptic];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                       message:@"This bookmark has an invalid coordinate."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    [store recordRecentCoordinate:bookmark.coordinate name:bookmark.name];
    [self playApplyHaptic];
    LSSetHooksBypassed(NO);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)ls_presentStaticMapActionSheetAtCoordinate:(CLLocationCoordinate2D)coordinate {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Place Pin Here" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf movePinToCoordinate:coordinate animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Save as Bookmark" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf presentSaveBookmarkAlertWithSuggestedName:nil coordinate:coordinate];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

@end
