#import "RLCLocationPickerViewController.h"
#import "RLCLocalize.h"
#import "RLCChinaCoords.h"
#import "RLCLocationPickerAdvancedSettingsListViewController.h"
#import "RLCFavorites.h"

@implementation RLCLocationPickerViewController

// Preferences still creates detail controllers through this selector, so it has
// to exist - removing it entirely made the row crash on tap with an unrecognised
// selector. It now only constructs the object; all view setup happens in
// -viewDidLoad, which is called regardless of how the controller was created.
- (id)initForContentSize:(CGSize)size {
    return [self init];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.lpView = [[RLCLocationPickerView alloc] initWithFrame:self.view.bounds
                                                    controller:self];
    self.lpView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                   UIViewAutoresizingFlexibleHeight;
    self.view = self.lpView;

    // Map style and altitude live behind a system sheet rather than in a drawer
    // sliding over the map.
    //
    // The drawer was a hand-rolled pan gesture over Auto Layout: it never followed
    // the finger, its own hit-test window covered the search field, and it needed
    // a custom overlay to dismiss. UISheetPresentationController, available since
    // iOS 15 which is this package's floor, does all of that natively - drag,
    // detents, tap-outside dismissal - and reads as part of the system.
    self.advancedSettingsButton =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showAdvancedSettings:)];
    self.advancedSettingsButton.tintColor = [UIColor blackColor];

    // Opens the joystick over this page. It is a tool for nudging the pin while
    // looking at the map, not a setting: nothing about it is remembered, and it
    // is off on every visit.
    self.joystickButton =
        [[UIBarButtonItem alloc] initWithTitle:RLCLocalized(@"JOYSTICK")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(toggleJoystick:)];
    self.joystickButton.tintColor = [UIColor blackColor];

    // Star: adds the current pin to the stored favourites.
    self.favoriteButton =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"star"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(favorite:)];
    self.favoriteButton.tintColor = [UIColor blackColor];

    self.savedButton =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"bookmark"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showFavorites:)];
    self.savedButton.tintColor = [UIColor blackColor];

    self.navigationItem.rightBarButtonItems =
        @[self.favoriteButton, self.savedButton, self.joystickButton, self.advancedSettingsButton];

    self.searchResultsController = [[RLCLocationPickerSearchResultsViewController alloc] init];
    self.searchResultsController.parentController = self;

    // The search field is a plain UISearchBar pinned over the map rather than
    // navigationItem.searchController: that form put the field underneath the
    // map view in this navigation stack, so touches landed on the map instead of
    // the bar. Owning the bar and adding it last guarantees it is on top.
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = RLCLocalized(@"SEARCH_PLACEHOLDER");
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.backgroundImage = [[UIImage alloc] init];      // no grey slab
    // A blurred pill behind the field, like the system map's search control. The
    // field is minimal-style, so without something behind it the placeholder sits
    // directly on the map and is unreadable over dark ground.
    self.searchBarBackdrop =
        [[UIVisualEffectView alloc] initWithEffect:
            [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
    self.searchBarBackdrop.userInteractionEnabled = NO;
    self.searchBarBackdrop.layer.cornerRadius = 10;
    self.searchBarBackdrop.layer.masksToBounds = YES;
    self.searchBarBackdrop.alpha = 0.7;      // let some of the map show through
    self.searchBarBackdrop.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBarBackdrop];

    self.searchController = [[UISearchController alloc]
                             initWithSearchResultsController:self.searchResultsController];
    self.searchController.searchResultsUpdater = self.searchResultsController;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = NO;

    // Both views must be in the hierarchy before a constraint can join them.
    // The results list was previously constrained to a search bar that had not
    // been added yet, which threw "no common ancestor" and terminated the app.
    [self.view addSubview:self.searchBar];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;

    [self addChildViewController:self.searchResultsController];
    [self.view addSubview:self.searchResultsController.view];
    self.searchResultsController.view.translatesAutoresizingMaskIntoConstraints = NO;

    // Results float under the search field on a translucent card, the way the
    // system's own map search does it: the map stays visible behind and around it,
    // so the list reads as something laid over the map rather than a second screen.
    //
    // Two earlier attempts got this wrong in opposite directions - a full-height
    // white slab cut the page in half, and dimming the map to fix that made the
    // whole thing grey and heavy.
    UIView *resultsView = self.searchResultsController.view;

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    UIVisualEffectView *backdrop = [[UIVisualEffectView alloc] initWithEffect:blur];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    backdrop.userInteractionEnabled = NO;
    backdrop.layer.cornerRadius = 12;
    backdrop.layer.masksToBounds = YES;
    [resultsView insertSubview:backdrop atIndex:0];

    resultsView.backgroundColor = [UIColor clearColor];
    resultsView.layer.cornerRadius = 12;
    resultsView.layer.masksToBounds = YES;

    [NSLayoutConstraint activateConstraints:@[
        [backdrop.topAnchor constraintEqualToAnchor:resultsView.topAnchor],
        [backdrop.leadingAnchor constraintEqualToAnchor:resultsView.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:resultsView.trailingAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:resultsView.bottomAnchor],
    ]];

    // Height follows the rows instead of filling the screen, capped so a long list
    // still leaves the map visible behind it.
    resultsView.clipsToBounds = YES;

    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:8],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-8],

        [self.searchBarBackdrop.topAnchor constraintEqualToAnchor:self.searchBar.topAnchor],
        [self.searchBarBackdrop.bottomAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.searchBarBackdrop.leadingAnchor constraintEqualToAnchor:self.searchBar.leadingAnchor],
        [self.searchBarBackdrop.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor],

        [resultsView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:4],
        [resultsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:10],
        [resultsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],
    ]];

    self.resultsHeightConstraint =
        [resultsView.heightAnchor constraintEqualToConstant:0];
    self.resultsHeightConstraint.active = YES;

    // Grows with the content, up to 55% of the screen height.
    // Capped so the card never becomes a full-screen sheet: it is a list hanging
    // under the field, not a page of its own.
    self.resultsMaxHeightConstraint =
        [resultsView.heightAnchor constraintLessThanOrEqualToAnchor:self.view.heightAnchor
                                                        multiplier:0.55];
    self.resultsMaxHeightConstraint.priority = UILayoutPriorityRequired;

    self.searchResultsController.view.hidden = YES;
    [self.searchResultsController didMoveToParentViewController:self];

    [self.lpView setPinGestureTarget:self];
    [self addRecentreButton];

    self.definesPresentationContext = YES;

    self.favorites = [NSMutableArray new];
    self.dictionary = [NSMutableDictionary new];

    HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
    id obj = [prefs objectForKey:@"Favorites"];
    if (obj && [obj isKindOfClass:[NSArray class]]) {
        self.favorites = [((NSArray *)obj) mutableCopy];
    }

    if ([prefs objectForKey:@"MapType"]) {
        switch ([[prefs objectForKey:@"MapType"] intValue]) {
            case 1:
                self.lpView.mapView.mapType = MKMapTypeSatellite;
                break;
            case 2:
                self.lpView.mapView.mapType = MKMapTypeHybrid;
                break;
            default:
                self.lpView.mapView.mapType = MKMapTypeStandard;
        }
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutRecentreButton];
}

- (void)viewWillAppear:(BOOL)animated {
    [self setTitle:[self navigationTitle]];
    [self.navigationItem setTitle:[self navigationTitle]];


    id value = [self readPreferenceValue:[self specifier]];
    if ([value isKindOfClass:[NSDictionary class]]) {
        self.dictionary = [(NSDictionary *)value mutableCopy];
        if (self.dictionary[@"Coordinate"]) {
            NSDictionary *coordinateDict = self.dictionary[@"Coordinate"];
            // Stored values are WGS-84 (what CLLocationManager reports); the map
            // draws GCJ-02, so the pin has to be shifted back onto it.
            CLLocationCoordinate2D stored = CLLocationCoordinate2DMake(
                [coordinateDict[@"Latitude"] doubleValue],
                [coordinateDict[@"Longitude"] doubleValue]);
            [self.lpView createPinAt:RLCWGS84ToGCJ02(stored)];
        }
    }
}

// Leaving the page is what saves it, and the stick belongs to this screen only.
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    // Only on a real pop, not when a sheet is being presented over this page.
    BOOL leaving = self.isMovingFromParentViewController ||
                   self.isBeingDismissed ||
                   self.navigationController.isBeingDismissed;
    if (leaving) {
        [self commitSelection];
        [self hideJoystick];
    }
}

- (NSString*)navigationTitle {
    return [[self specifier] name] ?: RLCLocalized(@"PICK_LOCATION_TITLE");
}

// Writing the chosen coordinate.
//
// There is no Save button and no confirmation step: the pin's position *is* the
// answer, so it is written as soon as it settles. Every path that can move the pin
// - a long press, a search result, the joystick coming to rest - ends here, which
// means the stored value always matches what is on screen.
//
// Rewriting the same coordinate is harmless (the tweak's next preference read
// picks it up either way), so there is no need to compare against what was last
// written.
// Called by the map when a drag of the pin finishes.
- (void)pinDidSettle {
    [self commitSelection];
}

- (void)commitSelection {
    if (!self.lpView.pin) return;

    // The pin sits on the GCJ-02 map; what the tweak must inject is WGS-84,
    // because that is the system CLLocationManager reports in.
    CLLocationCoordinate2D wgs = RLCGCJ02ToWGS84(self.lpView.pin.coordinate);
    self.dictionary[@"Coordinate"] = @{
        @"Latitude": @(wgs.latitude),
        @"Longitude": @(wgs.longitude)
    };

    NSString *key = [[self specifier] propertyForKey:@"key"];
    NSString *domain = [[self specifier] propertyForKey:@"defaults"]
                       ?: @"com.jzksnsjswkw.relocate";

    if (key.length) {
        // Written straight to the domain rather than through
        // -setPreferenceValue:specifier:.
        //
        // That method exists on PSViewController but goes through the controller's
        // own specifier plumbing, which only republishes the value it was handed
        // the first time; later calls updated the in-memory dictionary and left the
        // stored one alone, so the second and every later pick was ignored.
        HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:domain];
        [prefs setObject:[self.dictionary copy] forKey:key];

        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR("com.jzksnsjswkw.relocate/ReloadPrefs"),
                                             NULL, NULL, YES);
    }

    if ([[self specifier] propertyForKey:@"key"] && [[[self specifier] propertyForKey:@"key"] isEqualToString:@"GlobalLocation"]) {
        HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
        [prefs removeObjectForKey:@"SelectedFavorite"];
    }
}

-(void)updateSavedFavorites {
    HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
    [prefs setObject:self.favorites forKey:@"Favorites"];
}

-(void)favorite:(id)sender {
    // Nothing to remember until the map has a position.
    if (!self.lpView.pin) return;

    [self.lpView hideCallouts];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:RLCLocalized(@"ADD_TO_FAVORITES")
        message:RLCLocalized(@"ENTER_NAME")
        preferredStyle:UIAlertControllerStyleAlert];

    __weak UIAlertController *weakAlert = alert;
    __weak NSMutableArray *weakFavorites = self.favorites;

    UIAlertAction* ok = [UIAlertAction actionWithTitle:RLCLocalized(@"OK_CONFIRM") style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action){
            NSString *name = [[(UITextField *)weakAlert.textFields[0] text]
                              stringByTrimmingCharactersInSet:
                                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];

            // Empty names are refused rather than stored: a favourites list of
            // blank rows cannot be told apart or used.
            if (!name.length) {
                UIAlertController *needsName = [UIAlertController
                    alertControllerWithTitle:RLCLocalized(@"ADD_TO_FAVORITES")
                                     message:RLCLocalized(@"ENTER_NAME")
                              preferredStyle:UIAlertControllerStyleAlert];
                [needsName addAction:[UIAlertAction actionWithTitle:RLCLocalized(@"OK_CONFIRM")
                                                              style:UIAlertActionStyleDefault
                                                            handler:nil]];
                [self presentViewController:needsName animated:YES completion:nil];
                return;
            }

            CLLocationCoordinate2D wgs = RLCGCJ02ToWGS84(self.lpView.pin.coordinate);
            NSDictionary *favorite = @{
                @"Name": name,
                @"Latitude": @(wgs.latitude),
                @"Longitude": @(wgs.longitude)
            };

            [weakFavorites addObject:favorite];
            [self updateSavedFavorites];

            UIAlertController* savedAlert = [UIAlertController alertControllerWithTitle:RLCLocalized(@"FAVORITES_TITLE")
                                        message:RLCLocalized(@"FAVORITE_SAVED")
                                        preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:RLCLocalized(@"OK_CONFIRM") style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * action) {}];
            [savedAlert addAction:defaultAction];
            [self presentViewController:savedAlert animated:YES completion:nil];
        }
    ];
    
    UIAlertAction* cancel = [UIAlertAction actionWithTitle:RLCLocalized(@"CANCEL") style:UIAlertActionStyleDefault
        handler:^(UIAlertAction * action) {
            [alert dismissViewControllerAnimated:YES completion:nil];
        }
    ];

    // Cancel first, confirm second: UIAlertController lays actions out in the
    // order they are added, so this puts 取消 on the left and 确定 on the right.
    [alert addAction:cancel];
    [alert addAction:ok];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Name";
        textField.keyboardType = UIKeyboardTypeDefault;
    }];

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Results visibility

// One place that shows or hides the results panel, so the map dim and the
// recentre button cannot get out of step with it.
- (void)setResultsVisible:(BOOL)visible {
    self.searchResultsController.view.hidden = !visible;
    // The list floats over the map's lower half; the button lives in that same
    // corner, so it would otherwise sit on top of the rows.
    self.recentreButton.hidden = visible;

    if (visible) [self updateResultsHeight];
}

// Sizes the card to its rows.
//
// A table view has no intrinsic height, so the container has to be told: the
// content size is only known once the search returns, which is why this runs from
// the results controller after reloading rather than from a constraint alone.
- (void)updateResultsHeight {
    UITableView *table = self.searchResultsController.tableView;
    if (!table) return;

    [table layoutIfNeeded];

    CGFloat rows = table.contentSize.height;
    if (rows <= 0) rows = 0;

    // Clamp to the cap here too: the constraint's constant cannot exceed the
    // less-than-or-equal limit, and an unsatisfiable pair makes Auto Layout pick
    // one and log the other.
    CGFloat cap = CGRectGetHeight(self.view.bounds) * 0.55;
    if (cap > 0 && rows > cap) {
        rows = cap;
        table.scrollEnabled = YES;
    } else {
        table.scrollEnabled = NO;
    }

    self.resultsHeightConstraint.constant = rows;
}

#pragma mark - UISearchBarDelegate

// These were lost in an earlier edit, which left the search bar with a delegate
// that implemented none of its methods: typing produced no callback and no
// search ever started.
- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
    if (searchBar.text.length) [self setResultsVisible:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    self.searchResultsController.pendingQuery = searchText;

    BOOL hasText = searchText.length > 0;
    [self setResultsVisible:hasText];
    if (hasText) {
        [self.searchResultsController updateSearchResultsForSearchController:nil];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = NO;
    searchBar.text = @"";
    [searchBar resignFirstResponder];
    [self setResultsVisible:NO];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

#pragma mark - Joystick

// Shows the stick over this page, for nudging the pin while watching the map.
//
// Nothing is persisted: the stick exists only while this picker is on screen, so
// every visit starts with it closed and the target app is never involved.
- (void)toggleJoystick:(id)sender {
    if (self.joystickWindow) {
        [self hideJoystick];
    } else {
        [self showJoystick];
    }
}

- (void)showJoystick {
    if (self.joystickWindow) return;

    // The stick moves the pin, so there has to be one.
    //
    // This was a guard that bailed out when pin was nil, which meant the stick
    // refused to appear on a page that had no position yet - the one case where
    // the user most needs it.
    //
    // Built here rather than through -createPinAt: because that also sets a region,
    // which would snap the map back to the default zoom the moment the stick was
    // opened. The pin belongs mid-screen, and the zoom should be left alone.
    if (!self.lpView.pin) {
        MKPointAnnotation *pin = [[MKPointAnnotation alloc] init];
        pin.coordinate = self.lpView.mapView.region.center;
        pin.title = RLCLocalized(@"SELECTED_LOCATION");

        self.lpView.pin = pin;
        [self.lpView.mapView addAnnotation:pin];
    }

    RLCJoystickView *stick = [[RLCJoystickView alloc] initWithFrame:self.lpView.bounds];
    stick.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                             UIViewAutoresizingFlexibleHeight;

    // Committed when the thumb is released, not on every frame: moving the pin
    // writes preferences, and doing that sixty times a second is pointless.
    __weak typeof(self) weakSelf = self;
    stick.onRelease = ^{
        [weakSelf commitSelection];
    };

    [self.lpView addSubview:stick];
    self.joystickWindow = stick;
    [self setJoystickButtonSelected:YES];

    self.joystickTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                        target:self
                                                      selector:@selector(stepPinFromJoystick:)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)hideJoystick {
    [self.joystickTimer invalidate];
    self.joystickTimer = nil;

    [self.joystickWindow removeFromSuperview];
    self.joystickWindow = nil;

    [self setJoystickButtonSelected:NO];
}

// A pressed look while the stick is up, so the button reports the state it owns.
- (void)setJoystickButtonSelected:(BOOL)selected {
    self.joystickButton.tintColor =
        selected ? [UIColor systemBlueColor] : [UIColor blackColor];
}

#pragma mark - Recentre

// The floating button above the joystick ring.
//
// Owned by the picker's view rather than the stick window so it stays put whether
// or not the stick is open: the position is a fixed slot, and the ring appears
// below it. Anchored to the bottom-right corner with the same 170pt inset the ring
// uses, so the two line up rather than merely looking close.
- (void)layoutRecentreButton {
    if (!self.recentreButton) return;

    CGRect bounds = self.lpView.bounds;
    CGFloat diameter = 44;
    // Same right inset as the ring, so the button sits in the ring's own column
    // rather than floating at the screen edge.
    self.recentreButton.frame = CGRectMake(CGRectGetWidth(bounds) - 34 - diameter,
                                           CGRectGetHeight(bounds) - 190 - diameter - 12,
                                           diameter, diameter);
}

- (void)addRecentreButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectZero;
    // Grey rather than the card colour: the button sits on the map, and a white
    // disc there reads as part of the map's own controls.
    button.backgroundColor = [UIColor secondarySystemBackgroundColor];
    button.tintColor = [UIColor labelColor];
    button.layer.cornerRadius = 22;
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOpacity = 0.2;
    button.layer.shadowOffset = CGSizeMake(0, 1);
    button.layer.shadowRadius = 4;

    // location.fill (SF Symbols 1) exists on every iOS this package supports.
    [button setImage:[UIImage systemImageNamed:@"location.fill"]
            forState:UIControlStateNormal];
    [button addTarget:self
               action:@selector(centreOnCurrentLocation:)
     forControlEvents:UIControlEventTouchUpInside];

    [self.lpView addSubview:button];
    self.recentreButton = button;
    [self layoutRecentreButton];
}

// Jumps to the position this page is about.
//
// Two cases, in the order the question is actually asked:
//
//   - the app has a stored coordinate - show that, since it is what the tweak is
//     injecting and what the user came here to check;
//   - it has none - fall back to where the device really is, which is the only
//     meaningful starting point before anything has been chosen.
//
// This used to always ask CoreLocation for a fix. In Preferences.app that request
// is refused: the process has no location usage description and no authorisation
// entry, so the button did nothing at all even when a coordinate was stored.
// Jumps to the position this page is about.
//
// Only handles the stored case. Reading the device's real position from here was
// tried four ways and does not work: Preferences.app has no location
// authorisation and cannot be given one, a standalone CLI has no entry in
// locationd's client registry (every variant of the entitlement came back
// kCLErrorDenied), and injecting SpringBoard ran into the same wall. So when no
// position has been chosen there is nothing to jump to, and the button says so
// rather than doing nothing.
- (void)centreOnCurrentLocation:(id)sender {
    if (!self.lpView.pin) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:nil
                             message:RLCLocalized(@"NO_SELECTED_LOCATION")
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:RLCLocalized(@"OK")
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(
        self.lpView.pin.coordinate, RLC_PICKER_SPAN_METERS, RLC_PICKER_SPAN_METERS);
    [self.lpView.mapView setRegion:region animated:YES];
}

- (void)stepPinFromJoystick:(NSTimer *)timer {
    RLCJoystickView *stick = self.joystickWindow;
    if (!stick || !self.lpView.pin) {
        [timer invalidate];
        self.joystickTimer = nil;
        return;
    }

    if (stick.inputX == 0 && stick.inputY == 0) return;

    // Step scaled to the visible map, not to a fixed number of degrees.
    //
    // A fixed 0.00001 deg/frame is about a metre - invisible at city zoom, so the
    // pin looked stuck. Tying the step to the region's span means the pin moves the
    // same fraction of the screen whether the map is zoomed in or out.
    MKCoordinateRegion region = self.lpView.mapView.region;
    double stepLat = region.span.latitudeDelta * 0.012;
    double stepLon = region.span.longitudeDelta * 0.012;

    CLLocationCoordinate2D coord = self.lpView.pin.coordinate;
    coord.latitude  += stick.inputY * stepLat;
    coord.longitude += stick.inputX * stepLon;
    [self.lpView.pin setCoordinate:coord];
}

#pragma mark - Favourites

// The stored places, as a sheet.
//
// The list controller is reused as-is rather than rebuilt here: it already owns
// renaming, deleting and reordering, and duplicating that would mean two places to
// keep in step.
- (void)showFavorites:(id)sender {
    RLCFavorites *list = [[RLCFavorites alloc] init];
    list.favorites = self.favorites;

    __weak typeof(self) weakSelf = self;
    list.onPick = ^(double latitude, double longitude) {
        // Stored values are WGS-84; the pin has to land on the GCJ-02 map.
        [weakSelf applyPickedCoordinate:RLCWGS84ToGCJ02(
            CLLocationCoordinate2DMake(latitude, longitude))];
    };

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;

    UISheetPresentationController *sheet = nav.sheetPresentationController;
    if (sheet) {
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                          UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
    }

    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Advanced settings

- (void)showAdvancedSettings:(id)sender {
    RLCLocationPickerAdvancedSettingsListViewController *list =
        [[RLCLocationPickerAdvancedSettingsListViewController alloc] init];
    list.parent = self;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    // A sheet without an action button: dragging it down is the way out, so a bar
    // button would just be a second control for the same thing.
    list.navigationItem.title = RLCLocalized(@"ADVANCED_SETTINGS");

    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    UISheetPresentationController *sheet = nav.sheetPresentationController;
    if (sheet) {
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent,
                          UISheetPresentationControllerDetent.largeDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 12;
    }
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - Search results

// Called by the results list when a row is tapped.
- (void)applyPickedCoordinate:(CLLocationCoordinate2D)coord {
    if (!self.lpView.pin) [self.lpView createPinAt:coord];
    else [self.lpView.pin setCoordinate:coord];
    [self.lpView.pin setTitle:RLCLocalized(@"SELECTED_LOCATION")];

    [self.lpView.mapView setRegion:
        MKCoordinateRegionMakeWithDistance(coord,
                                           RLC_PICKER_SPAN_METERS,
                                           RLC_PICKER_SPAN_METERS)
                            animated:YES];

    [self setResultsVisible:NO];
    self.searchBar.text = @"";
    self.searchBar.showsCancelButton = NO;
    [self.searchBar resignFirstResponder];

    [self commitSelection];
}

@end