#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>
#import "HBPreferences.h"

@interface RLCFavorites : PSViewController <UITableViewDelegate,UITableViewDataSource> {
    UITableView *_tableView;
}

@property (nonatomic, retain) NSMutableArray *favorites;
@property (nonatomic, retain) UIBarButtonItem *editButton;

// The row the user tapped, and a way to hand it back.
//
// This list has no map of its own: choosing a favourite is about where to put the
// pin on the picker that opened it, so the value travels back instead of being
// shown here.
@property (nonatomic, copy) NSString *pickedName;
@property (nonatomic, assign) double pickedLatitude;
@property (nonatomic, assign) double pickedLongitude;
@property (nonatomic, copy) void (^onPick)(double latitude, double longitude);
- (void)refreshList;

@end