#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <AltList/ATLApplicationListSubcontrollerController.h>
#import <AltList/ATLApplicationSection.h>
#import <AltList/LSApplicationProxy+AltList.h>
#import "HBPreferences.h"

// A list of apps where each row opens that app's settings page.
//
// ATLApplicationListSubcontrollerController is the base class for exactly this
// shape - a list whose rows drill into a per-item controller - so the table,
// search, icons and chevrons are the framework's. The multi-selection and
// selection bases were the wrong fit: the first forces a switch (Relocate's
// per-app state is three-way, not a boolean) and the second forces a checkmark.
@interface RLCAppListController : ATLApplicationListSubcontrollerController
@end
