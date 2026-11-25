#import "RLCLocationPickerSearchResultsViewController.h"
#import "RLCLocalize.h"
#import "RLCChinaCoords.h"
#import "RLCLocationPickerViewController.h"

@implementation RLCLocationPickerSearchResultsViewController

- (id)init {
    self = [super init];
    self.items = @[];
    self.allowDeletion = NO;
    return self;
}

-(void)viewDidLoad {
    [super viewDidLoad];

    // Own table view: this used to be a UITableViewController shown by
    // UISearchController, but the picker now hosts a plain UISearchBar, so
    // nothing displayed these results. It is added into the picker's view tree
    // and sized there.
    // Constrained to its container, not given self.view.bounds as a frame.
    //
    // In -viewDidLoad that bounds is still zero: the view has not been laid out
    // yet. A zero frame plus an autoresizing mask only corrects itself when the
    // parent later changes size, which never happens here - the result was a table
    // one row tall with the rest clipped away.
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero
                                                  style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.allowsMultipleSelectionDuringEditing = NO;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    // The card behind is translucent and rounded; the table must be too, or its
    // opaque rows would square off the corners it sits inside.
    self.tableView.layer.masksToBounds = YES;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 44, 0, 16);
    // Bouncing is off because the card sizes to its rows - except when the rows
    // exceed the card's cap, where scrolling is the only way to reach them.
    self.tableView.alwaysBounceVertical = NO;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

-(void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    // Called both by the framework (searchController non-nil) and directly from
    // the picker's UISearchBar delegate, where there is no controller to read.
    NSString *query = searchController.searchBar.text ?: self.pendingQuery;
    if (!query.length) return;

    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;

    // Without a region, the search is biased to wherever the system defaults to
    // rather than to the map on screen, and a local-looking query returns a single
    // far-away match. Pointing it at the visible area is what makes the list a list.
    if ([self.parentController isKindOfClass:[RLCLocationPickerViewController class]]) {
        RLCLocationPickerViewController *picker =
            (RLCLocationPickerViewController *)self.parentController;
        request.region = picker.lpView.mapView.region;
    }

    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        if (error) {
            NSLog(@"[Relocate] search '%@' failed: %@", query, error);
            self.items = @[];
            [self.tableView reloadData];
            return;
        }
        self.allowDeletion = NO;
        self.items = response.mapItems ?: @[];
        NSLog(@"[Relocate] search '%@' -> %lu result(s)", query,
              (unsigned long)self.items.count);
        [self.tableView reloadData];

        // The card is sized from the row heights, which only exist after the
        // reload; without this it stays at whatever height it had.
        [self.tableView layoutIfNeeded];
        if ([self.parentController isKindOfClass:[RLCLocationPickerViewController class]]) {
            [(RLCLocationPickerViewController *)self.parentController updateResultsHeight];
        }
    }];
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"cell"];
        cell.backgroundColor = [UIColor clearColor];
        // The blurred card supplies the backdrop; an opaque row would punch a
        // white hole in it.
        cell.contentView.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    }

    if (indexPath.row >= (NSInteger)self.items.count) return cell;
    id item = [self.items objectAtIndex:indexPath.row];

    if ([item isKindOfClass:[MKMapItem class]]) {
        MKPlacemark *placemark = ((MKMapItem *)item).placemark;
        cell.textLabel.text = placemark.name ?: placemark.title;
        cell.detailTextLabel.text = placemark.title;
        // The location pin the system map search uses, so a row is identifiable as
        // a place at a glance instead of reading as a plain line of text.
        cell.imageView.image = [UIImage systemImageNamed:@"mappin.circle.fill"];
        cell.imageView.tintColor = [UIColor secondaryLabelColor];
    } else if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = item;
        cell.textLabel.text = dict[@"Name"];
    } else {
        cell.textLabel.text = RLCLocalized(@"ERROR");
    }

    return cell;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.items.count) return;
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(0, 0);

    id item = [self.items objectAtIndex:indexPath.row];

    if ([item isKindOfClass:[MKMapItem class]]) {
        coord = ((MKMapItem *)item).placemark.coordinate;
    } else if ([item isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = item;
        coord = CLLocationCoordinate2DMake([dict[@"Latitude"] doubleValue],
                                           [dict[@"Longitude"] doubleValue]);
    }

    // Imported by the picker, which owns the map; this controller is an inline
    // overlay now, not a modal, so it does not dismiss itself.
    UIViewController *parent = self.parentController;
    if ([parent isKindOfClass:[RLCLocationPickerViewController class]]) {
        [(RLCLocationPickerViewController *)parent applyPickedCoordinate:coord];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.allowDeletion;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    if (indexPath.row >= (NSInteger)self.items.count) return;

    RLCLocationPickerViewController *picker =
        (RLCLocationPickerViewController *)self.parentController;
    if (![picker isKindOfClass:[RLCLocationPickerViewController class]]) return;

    [picker.favorites removeObjectAtIndex:indexPath.row];
    [picker updateSavedFavorites];
    [self.tableView reloadData];
}

@end
