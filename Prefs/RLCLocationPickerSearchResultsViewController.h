#import <MapKit/MapKit.h>

#import <UIKit/UIKit.h>

@interface RLCLocationPickerSearchResultsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, retain) UITableView *tableView;

@property (nonatomic, retain) NSArray *items;
@property (nonatomic, retain) UIViewController *parentController;
@property (nonatomic, assign) BOOL allowDeletion;
@property (nonatomic, copy) NSString *pendingQuery;

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController;

@end