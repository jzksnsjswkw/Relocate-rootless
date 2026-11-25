#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@class RLCLocationPickerViewController;

@interface RLCLocationPickerAdvancedSettingsListViewController : PSListController {
    UITableView * _table;
}

// The map page the sheet was opened from, and the object the rows read and write.
@property (nonatomic, assign) RLCLocationPickerViewController *parent;

-(UITableView *)table;

@end