
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListController.h>
#import "HBPreferences.h"
#import "RLCLocationPickerView.h"
#import "RLCLocationPickerSearchResultsViewController.h"
#import "RLCJoystickView.h"

@interface RLCLocationPickerViewController : PSViewController <UISearchBarDelegate>

@property (nonatomic, retain) UISearchBar *searchBar;
@property (nonatomic, retain) RLCLocationPickerSearchResultsViewController *searchResultsController;
-(void)commitSelection;
-(void)pinDidSettle;
-(void)setResultsVisible:(BOOL)visible;
-(void)updateResultsHeight;
@property (nonatomic, retain) UIBarButtonItem *advancedSettingsButton;
@property (nonatomic, retain) UIBarButtonItem *joystickButton;
@property (nonatomic, retain) RLCJoystickView *joystickWindow;
@property (nonatomic, retain) NSTimer *joystickTimer;
@property (nonatomic, retain) UIBarButtonItem *favoriteButton;
@property (nonatomic, retain) UIBarButtonItem *savedButton;
@property (nonatomic, retain) UIButton *recentreButton;
@property (nonatomic, retain) UIVisualEffectView *searchBarBackdrop;
@property (nonatomic, retain) NSLayoutConstraint *resultsHeightConstraint;
@property (nonatomic, retain) NSLayoutConstraint *resultsMaxHeightConstraint;
@property (nonatomic, retain) RLCLocationPickerView *lpView;
@property (nonatomic, retain) NSMutableArray *favorites;
@property (nonatomic, retain) NSMutableDictionary *dictionary;
-(void)applyPickedCoordinate:(CLLocationCoordinate2D)coordinate;
-(void)updateSavedFavorites;
-(void)showAdvancedSettings:(id)sender;
-(void)showFavorites:(id)sender;
-(void)toggleJoystick:(id)sender;
-(void)centreOnCurrentLocation:(id)sender;


@end