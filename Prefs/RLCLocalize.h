// RLCLocalize.h - one entry point for strings the code shows.
//
// The plist-driven cells are localised by the Preferences framework itself: their
// "label" values are keys (ENABLED, GLOBAL, ...) resolved against the bundle's
// .lproj/*.strings. Strings that the code creates - alerts, buttons, the search
// placeholder - bypass that mechanism entirely, so they go through here.
//
// Every key also has an entry in base.lproj/Localizable.strings (English), so a
// missing translation degrades to readable English rather than the raw key.

#import <Foundation/Foundation.h>

/// Looks the key up in this bundle's Localizable.strings table.
NSString *RLCLocalized(NSString *key);
