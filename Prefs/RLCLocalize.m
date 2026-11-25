// RLCLocalize.m - see RLCLocalize.h.

#import "RLCLocalize.h"

NSString *RLCLocalized(NSString *key) {
    if (!key.length) return @"";

    // The bundle the caller expects is the preference bundle this code ships in.
    // NSLocalizedString would look in the main bundle, which for a preference
    // bundle host is Preferences.app - not us.
    static NSBundle *bundle = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bundle = [NSBundle bundleForClass:NSClassFromString(@"RLCPrefsListController")];
    });

    NSString *value = [bundle localizedStringForKey:key value:nil table:@"Localizable"];
    // A missing key comes back as the key itself; that is still better than nil.
    return value ?: key;
}
