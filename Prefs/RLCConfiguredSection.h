#import <Foundation/Foundation.h>

// Whether an app has a per-app setting that the user actually changed.
//
// Stored as App_<bundle id>_Enabled, where 0 means "default" - untouched - and 1
// or 2 are the two overrides. Only the latter two count as configured, otherwise
// it would match nearly every app on the device.
BOOL RLCApplicationHasStoredSetting(NSString *applicationIdentifier);

// A digest of every per-app mode, used to tell whether the list needs rebuilding.
// Reading the whole domain here is cheaper than reloading several hundred rows and
// their icons just to find out nothing changed.
NSString *RLCApplicationModesFingerprint(void);
