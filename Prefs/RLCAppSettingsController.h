#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "HBPreferences.h"

// Per-app settings page.
//
// The app it configures is handed over through +setNextApplicationID: right
// before it is pushed, rather than read from AltList at render time - see the
// note in the implementation.
@interface RLCAppSettingsController : PSListController
@property (nonatomic, copy) NSString *applicationID;
+ (void)setNextApplicationID:(NSString *)identifier;
@end
