#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "HBPreferences.h"
#import "NSTask.h"

@interface RLCPrefsListController : PSListController
    - (void)resetPrefs:(id)sender;
    - (void)respring:(id)sender;
    - (void)openGitHub:(id)sender;
@end