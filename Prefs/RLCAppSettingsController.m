#include "RLCAppSettingsController.h"
#import <AltList/LSApplicationProxy+AltList.h>

// Per-app settings.
//
// Every row in AppSettings.plist carries a short "key" ("Enabled", "Location",
// "Joystick"). This page rewrites those into "App_<bundle>_<key>" so two apps
// cannot share a value, and so the tweak's App_ lookup finds them.
//
// The bundle identifier arrives on a class-level handover rather than through
// AltList's -applicationID: that property exists, but AltList assigns it at a
// point that proved unreliable to observe, and the page rendered empty when the
// rows were built too early. A static handover is set by the list immediately
// before it pushes this controller, which is deterministic.
@implementation RLCAppSettingsController {
    NSString *_rlcBundleIdentifier;
}

static NSString *gRLCPendingBundleIdentifier = nil;

+ (void)setNextApplicationID:(NSString *)identifier {
    gRLCPendingBundleIdentifier = [identifier copy];
}

+ (NSString *)takeNextApplicationID {
    NSString *value = gRLCPendingBundleIdentifier;
    gRLCPendingBundleIdentifier = nil;
    return value;
}

- (NSString *)rlc_bundleIdentifier {
    if (_rlcBundleIdentifier.length) return _rlcBundleIdentifier;

    // Take the handover once; afterwards it is this page's own.
    NSString *handed = [[self class] takeNextApplicationID];
    if (handed.length) _rlcBundleIdentifier = handed;
    return _rlcBundleIdentifier;
}

// The one place rows are built. By the time this runs the identifier is known,
// so the prefix is right the first time.
- (id)specifiers {
    if (!_specifiers) {
        NSString *bundle = [self rlc_bundleIdentifier];

        _specifiers = [self loadSpecifiersFromPlistName:@"AppSettings" target:self];

        if (bundle.length) {
            for (PSSpecifier *row in _specifiers) {
                NSString *key = [row propertyForKey:@"key"];
                if (!key.length || [key hasPrefix:@"App_"]) continue;
                [row setProperty:[NSString stringWithFormat:@"App_%@_%@", bundle, key]
                          forKey:@"key"];
            }
        }

        NSString *title = [self.specifier name];
        if (!title.length && bundle.length) {
            LSApplicationProxy *proxy =
                [LSApplicationProxy applicationProxyForIdentifier:bundle];
            title = [proxy atl_nameToDisplay] ?: bundle;
        }
        if (title.length) {
            self.title = title;
            self.navigationItem.title = title;
        }
    }
    return _specifiers;
}

// AltList's subcontroller path: expected, but no longer depended upon.
- (void)setApplicationID:(NSString *)applicationID {
    _rlcBundleIdentifier = [applicationID copy];
}

- (bool)shouldReloadSpecifiersOnResume {
    return NO;
}

@end
