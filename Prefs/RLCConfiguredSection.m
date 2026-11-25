#import "RLCConfiguredSection.h"
#import "HBPreferences.h"

BOOL RLCApplicationHasStoredSetting(NSString *applicationIdentifier) {
    if (!applicationIdentifier.length) return NO;

    static HBPreferences *prefs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefs = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
    });

    NSString *key = [NSString stringWithFormat:@"App_%@_Enabled", applicationIdentifier];
    return [[prefs objectForKey:key] intValue] != 0;
}

NSString *RLCApplicationModesFingerprint(void) {
    static HBPreferences *prefs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefs = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
    });

    NSDictionary *all = [prefs dictionaryRepresentation];
    NSArray *keys = [[all allKeys] sortedArrayUsingSelector:@selector(compare:)];

    NSMutableString *digest = [NSMutableString string];
    for (NSString *key in keys) {
        if (![key hasPrefix:@"App_"] || ![key hasSuffix:@"_Enabled"]) continue;
        [digest appendFormat:@"%@=%@;", key, all[key]];
    }
    return digest;
}
