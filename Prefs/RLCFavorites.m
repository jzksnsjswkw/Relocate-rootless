#import "RLCFavorites.h"
#import "RLCLocalize.h"
#define BUNDLE_ID @"com.jzksnsjswkw.relocate"

@implementation RLCFavorites

// See RLCLocationPickerViewController: Preferences constructs detail
// controllers through this selector, so it must remain.
- (id)initForContentSize:(CGSize)size {
    return [self init];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    {
        self.favorites = [NSMutableArray new];
        _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
        _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_tableView setDataSource:self];
        [_tableView setDelegate:self];
        [_tableView setEditing:NO];
        [_tableView setAllowsSelection:YES];
        [_tableView setAllowsMultipleSelection:NO];

        self.editButton = [[UIBarButtonItem alloc] initWithTitle:RLCLocalized(@"EDIT") 
                            style:UIBarButtonItemStylePlain
                            target:self 
                            action:@selector(toggleEditing:)];
        self.editButton.tintColor = [UIColor blackColor];
        self.navigationItem.rightBarButtonItem = self.editButton;
        
        self.view = _tableView;
    }
}

- (void)toggleEditing:(id)sender {
    if ([_tableView isEditing]) {
        [self.editButton setTitle:RLCLocalized(@"EDIT")];
    } else {
        [self.editButton setTitle:RLCLocalized(@"CONFIRM")];
    }
    [_tableView setEditing:![_tableView isEditing]];
}

- (void)loadFromSpecifier:(PSSpecifier *)specifier {
    NSString *title = [specifier name];
    [self setTitle:title];
    [self.navigationItem setTitle:title];
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    [self loadFromSpecifier:specifier];
    [super setSpecifier:specifier];
}

- (void)refreshList {
    HBPreferences *file = [[HBPreferences alloc] initWithIdentifier:BUNDLE_ID];
    self.favorites = [file objectForKey:@"Favorites"];
    [_tableView reloadData];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef)@"com.jzksnsjswkw.relocate/ReloadPrefs", nil, nil, true);
}

- (id)view {
    return _tableView;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear: animated];
    [self refreshList];
}

- (NSString*)navigationTitle {
    return RLCLocalized(@"FAVORITES_TITLE");
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.favorites.count;
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SettingsCell"];
    }
    
    NSDictionary *favorite = [self.favorites objectAtIndex:indexPath.row];
    cell.textLabel.text = favorite[@"Name"];    
    cell.selected = NO;

    return cell;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.row >= (NSInteger)self.favorites.count) return;
    NSDictionary *favorite = self.favorites[indexPath.row];

    // Picked for the map to jump to, so the picker can show it there rather than
    // this page trying to draw a map of its own.
    NSString *name = favorite[@"Name"];
    self.pickedName = name;
    self.pickedLatitude = [favorite[@"Latitude"] doubleValue];
    self.pickedLongitude = [favorite[@"Longitude"] doubleValue];

    if (self.onPick) {
        self.onPick(self.pickedLatitude, self.pickedLongitude);
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:BUNDLE_ID];
    NSMutableArray *favorites = nil;

    if ([prefs objectForKey:@"Favorites"]) {
        favorites = [[prefs objectForKey:@"Favorites"] mutableCopy];
        NSMutableDictionary *dictionary = favorites[sourceIndexPath.row];
        [favorites removeObjectAtIndex:sourceIndexPath.row];
        [favorites insertObject:dictionary atIndex:destinationIndexPath.row];
    } else {
        favorites = [@[] mutableCopy];
    }

    [prefs setObject:favorites forKey:@"Favorites"];
}

-(NSArray *)tableView:(UITableView *)tableView editActionsForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewRowAction *renameAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:RLCLocalized(@"RENAME") handler:^(UITableViewRowAction *action, NSIndexPath *indexPath) {
        NSDictionary *favorite = (NSDictionary*)[self.favorites objectAtIndex:indexPath.row];
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:RLCLocalized(@"FAVORITES_TITLE")
            message:RLCLocalized(@"ENTER_NAME")
            preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction* ok = [UIAlertAction actionWithTitle:RLCLocalized(@"OK") style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * action){
                HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:BUNDLE_ID];
    
                NSMutableArray *favorites = nil;

                if ([prefs objectForKey:@"Favorites"]) {
                    favorites = [[prefs objectForKey:@"Favorites"] mutableCopy];
                    NSMutableDictionary *dictionary = [favorites[indexPath.row] mutableCopy];
                    dictionary[@"Name"] = [alert.textFields[0] text];
                    favorites[indexPath.row] = dictionary;
                } else {
                    favorites = [@[] mutableCopy];
                }

                [prefs setObject:favorites forKey:@"Favorites"];
                [self refreshList];
            }
        ];
        
        UIAlertAction* cancel = [UIAlertAction actionWithTitle:RLCLocalized(@"CANCEL") style:UIAlertActionStyleDefault
            handler:^(UIAlertAction * action) {
                [alert dismissViewControllerAnimated:YES completion:nil];
            }
        ];

        [alert addAction:ok];
        [alert addAction:cancel];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"Name";
            textField.keyboardType = UIKeyboardTypeDefault;
            textField.text = favorite[@"Name"];
        }];

        [self presentViewController:alert animated:YES completion:nil];
    }];
    renameAction.backgroundColor = [UIColor colorWithRed:0.27 green:0.47 blue:0.56 alpha:1.0];

    UITableViewRowAction *deleteAction = [UITableViewRowAction rowActionWithStyle:UITableViewRowActionStyleNormal title:RLCLocalized(@"DELETE") handler:^(UITableViewRowAction *action, NSIndexPath *indexPath) {
        HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:BUNDLE_ID];
        
        NSMutableArray *favorites = nil;

        if ([prefs objectForKey:@"Favorites"]) {
            favorites = [[prefs objectForKey:@"Favorites"] mutableCopy];
            [favorites removeObjectAtIndex:indexPath.row];
        } else {
            favorites = [@[] mutableCopy];
        }

        [prefs setObject:favorites forKey:@"Favorites"];
        [self refreshList];
    }];
    deleteAction.backgroundColor = [UIColor redColor];

    return @[deleteAction, renameAction];
}

@end