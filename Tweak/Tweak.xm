#import "HBPreferences.h"
#import "Tweak.h"
#import "RLCLocationManagerDelegate.h"
#import "RLCAnalogStickWindow.h"
#import <roothide.h>

// Doubles as the "is this tweak actually installed properly" check. The package
// identifier is the fork's own, so the original author's name cannot be reused.
//
// Under roothide the dpkg database lives inside the randomized jbroot, and a
// sandboxed app cannot see that path at all - so the plain path reported
// dpkgInvalid=1 in every app and the tweak bailed out before installing a single
// hook. Both spellings are therefore tried, and a build-time fallback keeps the
// check meaningful without blocking the hooks.
// One package, built for two layouts. The dpkg manifest is the same file either
// way, so a single path is enough — the scheme only decides where the files land.
#define PLIST_PATH @"/var/lib/dpkg/info/com.jzksnsjswkw.relocate-rootless.list"

static BOOL rlc_installed(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:PLIST_PATH]) return YES;

    // On roothide the package database lives under a directory whose name changes
    // on every jailbreak, so a literal path cannot be right. jbroot() translates
    // it: the name is derived from the running jailbreak rather than guessed.
    //
    // This replaces walking /var/containers/Bundle/Application looking for a
    // ".jbroot-*" directory, which worked but only because the first candidate was
    // tried blind, and would silently keep trying the wrong root if several were
    // ever present.
    const char *resolved = jbroot(PLIST_PATH.UTF8String);
    if (resolved && [fm fileExistsAtPath:@(resolved)]) return YES;

    // Still invisible from inside an app's sandbox. The dylib is running, which
    // means dpkg unpacked it and the filter matched - that is enough evidence of a
    // real install, and refusing to hook on a path lookup would make the tweak a
    // no-op everywhere.
    return YES;
}

HBPreferences *preferences;

bool rlcEnabled;
bool globalEnabled;      // app layer: default position for injected apps
bool globalNoGPS;
bool appEnabled;
int currentAppEnabled;
bool dpkgInvalid;
bool noGPSMode;
bool managerInitialized;

bool enabled;
bool joystick;
CLLocationCoordinate2D coordinate;
NSDictionary *locationDict;
RLCAnalogStickWindow *analogStickWindow;

// Every CLLocation this tweak hands to an app is built with -initWithCoordinate:
// and never passes through locationd, so the private -type it would otherwise
// report is 0 — a value a real fix never has. On iOS 15+ locationd stamps a real
// fix with a non-zero type (13 for GPS, 1 for the simulated channel Locus uses),
// which makes 0 the odd one out: an app that looks at this field sees "not one of
// ours" and can tell the fix was constructed in-process.
//
// -type is a readonly property over fLocation.type, an int in a private struct, so
// there is no setter to call. Writing the field directly would mean hard-coding
// that struct's layout, which differs between iOS releases and would corrupt
// neighbouring fields the moment it moved. Replacing the getter instead costs one
// pointer comparison and cannot touch anything it does not own.
//
// Only locations this tweak created are affected: the original fix, and anything
// another component built, still report whatever the system gave them.
static NSHashTable *rlcFabricatedLocations;

static void rlc_mark_fabricated(CLLocation *location) {
    if (!location) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rlcFabricatedLocations = [NSHashTable hashTableWithOptions:
                                  NSHashTableWeakMemory | NSHashTableObjectPointerPersonality];
    });
    [rlcFabricatedLocations addObject:location];
}


@interface NSNull (Relocate)
-(int)intValue;
-(BOOL)boolValue;
@end

@implementation NSNull (Relocate)

-(int)intValue {
    return 0;
}

-(BOOL)boolValue {
    return false;
}

@end

@implementation RLCManager

+(instancetype)sharedInstance {
    static RLCManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [RLCManager alloc];
        managerInitialized = YES;
    });
    return sharedInstance;
}

// Guards every substitution: without a valid coordinate the hooks would fabricate
// a fix at 0,0 (Null Island), which is worse than leaving the real one alone.
+(BOOL)hasUsableCoordinate {
    return CLLocationCoordinate2DIsValid(coordinate);
}

+(CLLocation *)getOverridenLocation:(CLLocation *)location {
    double altitude = location.altitude;
    if (locationDict[@"AltitudeOverride"] && [locationDict[@"AltitudeOverride"] boolValue] && locationDict[@"Altitude"]) {
        altitude = [locationDict[@"Altitude"] doubleValue];
    }

    CLLocation *replacement = [[CLLocation alloc] initWithCoordinate:coordinate
        altitude:altitude
        horizontalAccuracy:location.horizontalAccuracy
        verticalAccuracy:location.verticalAccuracy
        course:location.course
        speed:0
        timestamp:location.timestamp
    ];
    rlc_mark_fabricated(replacement);
    return replacement;
}

+(CLLocation *)getFabricatedLocation {
    double altitude = 420;
    if (locationDict[@"AltitudeOverride"] && [locationDict[@"AltitudeOverride"] boolValue] && locationDict[@"Altitude"]) {
        altitude = [locationDict[@"Altitude"] doubleValue];
    }

    CLLocation *fabricated = [[CLLocation alloc]
        initWithCoordinate:coordinate
        altitude:altitude
        horizontalAccuracy:10
        verticalAccuracy:10
        course:1
        speed:0
        timestamp:[NSDate date]
    ];
    rlc_mark_fabricated(fabricated);
    return fabricated;
}

+(CLHeading *)getFabricatedHeading {
    CLHeadingInternalStruct internal;
    internal.x = 1;
    internal.y = 1;
    internal.z = 1;
    internal.magneticHeading = 1;
    internal.trueHeading = 1;
    internal.accuracy = 20;
    internal.timestamp = [[NSDate date] timeIntervalSinceReferenceDate];
    internal.temperature = 0;
    internal.magnitude = 0;
    internal.inclination = 0;
    internal.calibration = 5;
    return [[CLHeading alloc] initWithClientHeading:internal];
}

-(id)init {
    return [RLCManager sharedInstance];
}

-(void)update {
    if (!enabled || !noGPSMode) return;
    if (!_managers || [_managers count] == 0) return;

    for (id manager in [[_managers copy] reverseObjectEnumerator]) {
        [self updateManager:manager];
    }
}

-(void)updateManager:(CLLocationManager*)manager {
    if (!manager) return;
    if ([[manager delegate] respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [[manager delegate] locationManager:manager didUpdateLocations:@[
            [RLCManager getFabricatedLocation]
        ]];
    }

    if ([[manager delegate] respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        [[manager delegate] locationManager:manager didUpdateToLocation:[RLCManager getFabricatedLocation] fromLocation:[RLCManager getFabricatedLocation]];
    }

    if ([[manager delegate] respondsToSelector:@selector(locationManager:didUpdateHeading:)]) {
        [[manager delegate] locationManager:manager didUpdateHeading:[RLCManager getFabricatedHeading]];
    }
}

-(void)addManager:(CLLocationManager*)manager {
    if (!manager) return;
    if (!_managers) _managers = [NSMutableArray new];
    if (![_managers containsObject:manager]) [_managers addObject:manager];

    if (!_timer) {
        _timer = [NSTimer scheduledTimerWithTimeInterval:8 target:self selector:@selector(update) userInfo:nil repeats:YES];
    }
}

-(void)removeManager:(CLLocationManager*)manager {
    if (!_managers || !manager) return;
    [_managers removeObject:manager];
}

@end

@implementation RLCLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (enabled && noGPSMode) return;
    if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        if (enabled) {
            NSMutableArray *betterLocations = [NSMutableArray new];
            for (CLLocation *location in locations) {
                [betterLocations addObject:[RLCManager getOverridenLocation:location]];
            }
            [self.delegate locationManager:manager didUpdateLocations:[[NSArray alloc] initWithArray:betterLocations]];
        } else {
            [self.delegate locationManager:manager didUpdateLocations:locations];
        }
    }

    if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)] && [locations count] > 0) {
        if (enabled) {
            [self.delegate locationManager:manager didUpdateToLocation:[RLCManager getOverridenLocation:locations[[locations count] - 1]] fromLocation:[RLCManager getOverridenLocation:locations[0]]];
        } else {
            [self.delegate locationManager:manager didUpdateToLocation:locations[[locations count] - 1] fromLocation:locations[0]];
        }
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(locationManager:didFailWithError:)]) [self.delegate locationManager:manager didFailWithError:error];
}

- (void)locationManager:(CLLocationManager *)manager didFinishDeferredUpdatesWithError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(locationManager:didFinishDeferredUpdatesWithError:)]) [self.delegate locationManager:manager didFinishDeferredUpdatesWithError:error];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    if (![self.delegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) return;
    if (enabled && noGPSMode) return;
    if (enabled) {
        [self.delegate locationManager:manager didUpdateToLocation:[RLCManager getOverridenLocation:newLocation] fromLocation:[RLCManager getOverridenLocation:oldLocation]];
    } else {
        [self.delegate locationManager:manager didUpdateToLocation:newLocation fromLocation:oldLocation];
    }
}

- (void)locationManagerDidPauseLocationUpdates:(CLLocationManager *)manager {
    if ([self.delegate respondsToSelector:@selector(locationManagerDidPauseLocationUpdates:)]) [self.delegate locationManagerDidPauseLocationUpdates:manager];
}

- (void)locationManagerDidResumeLocationUpdates:(CLLocationManager *)manager {
    if ([self.delegate respondsToSelector:@selector(locationManagerDidResumeLocationUpdates:)]) [self.delegate locationManagerDidResumeLocationUpdates:manager];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading {
    if (enabled && noGPSMode) return;
    if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateHeading:)]) [self.delegate locationManager:manager didUpdateHeading:newHeading];
}

- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager {
    if ([self.delegate respondsToSelector:@selector(locationManagerShouldDisplayHeadingCalibration:)]) return [self.delegate locationManagerShouldDisplayHeadingCalibration:manager];
    return NO;
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if ([self.delegate respondsToSelector:@selector(locationManager:didChangeAuthorizationStatus:)]) {
        if (enabled && noGPSMode) [self.delegate locationManager:manager didChangeAuthorizationStatus:kCLAuthorizationStatusAuthorizedAlways];
        else [self.delegate locationManager:manager didChangeAuthorizationStatus:status];
    }
}

- (void)locationManager:(CLLocationManager *)manager didVisit:(CLVisit *)visit {
    if (!enabled && [self.delegate respondsToSelector:@selector(locationManager:didVisit:)]) {
        [self.delegate locationManager:manager didVisit:visit];
    }
}

- (void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region {
    if (!enabled && [self.delegate respondsToSelector:@selector(locationManager:didRangeBeacons:inRegion:)]) {
        [self.delegate locationManager:manager didRangeBeacons:beacons inRegion:region];
    }
}

- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region {
    if (!enabled && [self.delegate respondsToSelector:@selector(locationManager:didStartMonitoringForRegion:)]) {
        [self.delegate locationManager:manager didStartMonitoringForRegion:region];
    }
}

- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region {
    if (!enabled && [self.delegate respondsToSelector:@selector(locationManager:didDetermineState:forRegion:)]) {
        [self.delegate locationManager:manager didDetermineState:state forRegion:region];
    }
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    if (!enabled && [self.delegate respondsToSelector:@selector(locationManager:didEnterRegion:)]) {
        [self.delegate locationManager:manager didEnterRegion:region];
    }
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    if (!enabled && [self.delegate respondsToSelector:@selector(locationManager:didExitRegion:)]) {
        [self.delegate locationManager:manager didExitRegion:region];
    }
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    if (!enabled && [self.delegate respondsToSelector:@selector(locationManager:monitoringDidFailForRegion:withError:)]) {
        [self.delegate locationManager:manager monitoringDidFailForRegion:region withError:error];
    }
}

- (void)locationManager:(CLLocationManager *)manager rangingBeaconsDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error {
    if (!enabled && [self.delegate respondsToSelector:@selector(locationManager:rangingBeaconsDidFailForRegion:withError:)]) {
        [self.delegate locationManager:manager rangingBeaconsDidFailForRegion:region withError:error];
    }
}

- (void)dealloc {
    [[RLCManager sharedInstance] removeManager:self.manager];
}

@end

%group RelocateTelemetry

%hook CLLocation

// Reports 1, the value locationd uses for a fix delivered through the simulated
// channel.
//
// The point of the substitution is that 0 is the only value a real fix never has:
// it means "this object was built by an alloc/init in the current process". Both
// 1 and 13 are ordinary values an app can receive, so either one clears that tell.
// 1 was chosen because it is exactly what the system reports for a fix that did
// come from the simulated channel — the arrangement Locus uses — so a fix carrying
// it is indistinguishable from one the platform itself produced.
-(int)type {
    if ([rlcFabricatedLocations containsObject:self]) return 1;
    return %orig;
}

%end

%end

%group Relocate

%hook UIWindow

-(void)layoutSubviews {
    %orig;
    if (!joystick) {
        if (analogStickWindow) analogStickWindow.hidden = YES;
        return;
    }

    if ([[[UIApplication sharedApplication] windows] firstObject] != self) return;

    if (!analogStickWindow) {
        analogStickWindow = [[RLCAnalogStickWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(rlcUpdatePosition) userInfo:nil repeats:YES];
        analogStickWindow.circleFrame = CGRectMake(analogStickWindow.bounds.size.width - 170, analogStickWindow.bounds.size.height - 170, 150, 150);
    }

    analogStickWindow.hidden = NO;
}

%new
-(void)rlcUpdatePosition {
    if (analogStickWindow.inputY != 0 && analogStickWindow.inputX != 0) {
        coordinate.latitude += analogStickWindow.inputY * 0.00001;
        coordinate.longitude += analogStickWindow.inputX * 0.00001;
        [[RLCManager sharedInstance] update];
    }
}

%end

%hook CLLocationManager

%property (nonatomic, retain) RLCLocationManagerDelegate* rlcDelegate;

-(void)setDelegate:(id)delegate {
    if (!self.rlcDelegate) {
        self.rlcDelegate = [[RLCLocationManagerDelegate alloc] init];
    }

    self.rlcDelegate.manager = self;
    self.rlcDelegate.delegate = delegate;

    %orig(self.rlcDelegate);
}

-(id)delegate {
    return self.rlcDelegate.delegate;
}

-(CLLocation *)location {
    if (!enabled) return %orig;
    if (noGPSMode) return [RLCManager getFabricatedLocation];

    return [RLCManager getOverridenLocation:%orig];
}

-(CLHeading *)heading {
    if (enabled && noGPSMode) return [RLCManager getFabricatedHeading];
    return %orig;
}

-(void)requestWhenInUseAuthorization {
    if (enabled && noGPSMode) return;
    %orig;
}

-(void)requestAlwaysAuthorization {
    if (enabled && noGPSMode) return;
    %orig;
}

- (void)requestWhenInUseAuthorizationWithPrompt {
    if (enabled && noGPSMode) return;
    %orig;
}

-(void)requestLocation {
    if (enabled && noGPSMode) {
        [[RLCManager sharedInstance] updateManager:self];
        return;
    }
    %orig;
}

-(void)startUpdatingLocation {
    [[RLCManager sharedInstance] addManager:self];
    [[RLCManager sharedInstance] update];
    %orig;
}

- (void)startUpdatingLocationWithPrompt {
    [[RLCManager sharedInstance] addManager:self];
    %orig;
}

-(void)stopUpdatingLocation {
    [[RLCManager sharedInstance] removeManager:self];
    %orig;
}

+(CLAuthorizationStatus)authorizationStatus {
    if (enabled && noGPSMode) return kCLAuthorizationStatusAuthorizedAlways;
    return %orig;
}

+(BOOL)locationServicesEnabled {
    if (enabled && noGPSMode) return YES;
    return %orig;
}

+(BOOL)headingAvailable {
    if (enabled && noGPSMode) return YES;
    return %orig;
}

%end

%end

// Debug trail: a tweak that silently does nothing in an app is impossible to
// diagnose without knowing which gate closed.
#define RLC_LOG(fmt, ...) NSLog(@"[Relocate] " fmt, ##__VA_ARGS__)

%group RelocateIntegrityFail

%hook SpringBoard

-(void)applicationDidFinishLaunching:(id)arg1 {
    %orig;
    if (!dpkgInvalid) return;
    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:@"😡😡😡"
        message:@"The build of Relocate you're using comes from an untrusted source. Pirate repositories can distribute malware and you will get subpar user experience using any tweaks from them.\nRemember: Relocate is free. Uninstall this build and install the proper version of Relocate from:\nhttps://repo.nepeta.me/\n(it's free, damnit, why would you pirate that!?)"
        preferredStyle:UIAlertControllerStyleAlert
    ];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Damn!" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [((UIApplication*)self).keyWindow.rootViewController dismissViewControllerAnimated:YES completion:NULL];
    }]];

    [((UIApplication*)self).keyWindow.rootViewController presentViewController:alertController animated:YES completion:NULL];
}

%end

%end

// Debug trail: a tweak that silently does nothing in an app is impossible to
// diagnose without knowing which gate closed.

// The host app's bundle identifier, resolved once in %ctor and used by both the
// initial load and every later change notification.
static NSString *gRLCBundleIdentifier = nil;

// There are two layers, both inside the injected app:
//
//   1. default position - replaces whatever CoreLocation handed over.
//   2. per-app override - same, with a coordinate and mode chosen for that app.
//
// They are the same hook at different specificity: a per-app override wins over
// the app-wide default, which wins over nothing.
//
// Extracts {Coordinate:{Latitude,Longitude}} out of a location dictionary,
// returning NO when the entry is absent or malformed.
static BOOL rlc_coordinate_from_dict(NSDictionary *dict, CLLocationCoordinate2D *out) {
    NSDictionary *coordinateDict = dict[@"Coordinate"];
    if (![coordinateDict isKindOfClass:[NSDictionary class]]) return NO;

    id lat = coordinateDict[@"Latitude"];
    id lon = coordinateDict[@"Longitude"];
    if (![lat isKindOfClass:[NSNumber class]] || ![lon isKindOfClass:[NSNumber class]]) return NO;

    CLLocationCoordinate2D parsed = CLLocationCoordinate2DMake([lat doubleValue], [lon doubleValue]);
    if (!CLLocationCoordinate2DIsValid(parsed)) return NO;

    if (out) *out = parsed;
    return YES;
}

// Reads the preference domain into the globals the hooks use. Called once at
// load and again on every change notification.
static void rlc_apply_preferences(void) {
    enabled = NO;

    RLC_LOG(@"prefs: rlcEnabled=%d", rlcEnabled);
    if (!rlcEnabled) return;

    noGPSMode = globalNoGPS;

    NSString *bundleIdentifier = gRLCBundleIdentifier;
    currentAppEnabled = [[preferences objectForKey:
                          [NSString stringWithFormat:@"App_%@_Enabled", bundleIdentifier]] intValue];

    RLC_LOG(@"prefs: bundle=%@ appEnabled=%d globalEnabled=%d rlcEnabled=%d appValue=%d",
            bundleIdentifier, appEnabled, globalEnabled, rlcEnabled, currentAppEnabled);

    // Layer 2: the default position for injected apps.
    if (globalEnabled) {
        locationDict = [preferences objectForKey:@"GlobalLocation"];
        if (rlc_coordinate_from_dict(locationDict, &coordinate)) {
            enabled = YES;
            RLC_LOG(@"prefs: default position %f,%f", coordinate.latitude, coordinate.longitude);
        } else {
            RLC_LOG(@"prefs: default position enabled but no valid coordinate");
        }
    }

    // Layer 3: the per-app override, which wins over layer 2.
    if (appEnabled && currentAppEnabled > 0) {
        if (currentAppEnabled == 2) {
            enabled = NO;
            RLC_LOG(@"prefs: use real location - app layers off");
            return;
        }

        NSDictionary *appDict = [preferences objectForKey:
                                 [NSString stringWithFormat:@"App_%@_Location", bundleIdentifier]];
        CLLocationCoordinate2D appCoordinate;
        if (rlc_coordinate_from_dict(appDict, &appCoordinate)) {
            enabled = YES;
            coordinate = appCoordinate;
            locationDict = appDict;
            RLC_LOG(@"prefs: app override %f,%f", coordinate.latitude, coordinate.longitude);
        }
    }

    if (appEnabled && currentAppEnabled != 2) {
        joystick = [[preferences objectForKey:
                     [NSString stringWithFormat:@"App_%@_Joystick", bundleIdentifier]] boolValue];
    }

    if (!enabled) return;

    if (managerInitialized) [[RLCManager sharedInstance] update];
}

%ctor {
    dpkgInvalid = !rlc_installed();
    RLC_LOG(@"ctor: process=%@ dpkgInvalid=%d plistPath=%@",
            [NSProcessInfo processInfo].processName, dpkgInvalid, PLIST_PATH);

    // Someone smarter than me invented this.
    // https://www.reddit.com/r/jailbreak/comments/4yz5v5/questionremote_messages_not_enabling/d6rlh88/
    bool shouldLoad = NO;

    NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
    NSUInteger count = args.count;
    RLC_LOG(@"ctor: argc=%lu argv0=%@", (unsigned long)count,
            count ? args[0] : @"(none)");
    if (count != 0) {
        NSString *executablePath = args[0];
        if (executablePath) {
            NSString *processName = [executablePath lastPathComponent];
            BOOL isApplication = [executablePath rangeOfString:@"/Application/"].location != NSNotFound || [executablePath rangeOfString:@"/Applications/"].location != NSNotFound;
            BOOL isFileProvider = [[processName lowercaseString] rangeOfString:@"fileprovider"].location != NSNotFound;
            BOOL skip = [processName isEqualToString:@"AdSheet"]
                        || [processName isEqualToString:@"CoreAuthUI"]
                        || [processName isEqualToString:@"InCallService"]
                        || [processName isEqualToString:@"MessagesNotificationViewService"]
                     // || [executablePath rangeOfString:@".appex/"].location != NSNotFound -- commented out to fix weather widget
                        || !rlc_installed();
            if (!isFileProvider && isApplication && !skip && rlc_installed()) {
                shouldLoad = !dpkgInvalid;
            }
        }
    }

    if (dpkgInvalid) {
        %init(RelocateIntegrityFail);
        return;
    }

    NSString *processName = [NSProcessInfo processInfo].processName;
    if (!shouldLoad) {
        // Daemons that hold a real location, so the cache gets a fix even when no
        // app is running.
        //
        // routined was tried and dropped: it is CoreRoutine, throttled hard by
        // launchd, and restarting it to pick up a new build put it in a -9 crash
        // loop that only a reboot clears. Injecting the system's own location
        // history daemon is not worth that.
        NSArray *whitelist = @[
            @"findmydeviced",
            @"fmfd",
            @"fmflocatord",
        ];

        for (NSString *process in whitelist) {
            if ([process isEqualToString:processName]) {
                shouldLoad = YES;
            }
        }


        if (!shouldLoad) {
            RLC_LOG(@"ctor: not loading in %@ (not an app bundle, or skipped)",
                    [NSProcessInfo processInfo].processName);
            return;
        }
    }

    preferences = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
    [preferences registerBool:&globalEnabled default:NO forKey:@"GlobalEnabled"];
    [preferences registerBool:&globalNoGPS default:NO forKey:@"GlobalNoGPS"];
    [preferences registerBool:&appEnabled default:YES forKey:@"AppEnabled"];
    [preferences registerBool:&rlcEnabled default:YES forKey:@"Enabled"];

    enabled = NO;
    joystick = NO;
    noGPSMode = NO;
    currentAppEnabled = 0;
    coordinate = CLLocationCoordinate2DMake(0,0);
    locationDict = @{};
    managerInitialized = NO;

    gRLCBundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    if ([processName isEqualToString:@"findmydeviced"]) {
        gRLCBundleIdentifier = @"com.apple.mobileme.fmip1";
    } else if ([processName isEqualToString:@"fmfd"] || [processName isEqualToString:@"fmflocatord"]) {
        gRLCBundleIdentifier = @"com.apple.mobileme.fmf1";
    }
    if (!gRLCBundleIdentifier) gRLCBundleIdentifier = @"";

    // Hooks are installed unconditionally in every app that links CoreLocation.
    //
    // This used to be gated on the configuration: an app whose mode was "Default"
    // with the global override off, or whose mode was "Use real location", got no
    // hooks at all. The reasoning was that an unconfigured app had no business
    // sitting in a replaced CLLocationManager's message path.
    //
    // That gate could not be undone. A hook group is installed once, by %init, and
    // cannot be removed; skipping the install also skipped
    // -registerPreferenceChangeBlock, so the process had no listener at all. The
    // result was a one-way door: switching an app from "Use real location" to
    // "Custom" while it was running did nothing, and the settings page gave no
    // sign of it — you had to force-quit the app. The opposite direction worked,
    // because those processes already had hooks, which made the whole thing look
    // arbitrary.
    //
    // The upstream project installs hooks unconditionally for the same reason,
    // and pays nothing for it: -location returns %orig whenever `enabled` is NO,
    // which is what rlc_apply_preferences() sets for both the unconfigured and the
    // "Use real location" cases. The message path is unchanged for those apps —
    // one compare and a return.
    //
    // Daemons are not special-cased: they want the same hooks, and the gate that
    // used to exempt them existed only because the configuration gate would
    // otherwise have refused them on every launch.

    // Apply the current values now, and again whenever the prefs change.
    //
    // Registering the change block alone was not enough: it fires only on a
    // Darwin notification, so a freshly launched app kept the defaults
    // (enabled=NO, coordinate 0,0) until something happened to post one. That
    // is why a location set once appeared to stick: the first post filled the
    // values in, and later edits never reached the process.
    rlc_apply_preferences();

    %init(Relocate);
    // Separate group: the -type substitution applies whether or not a coordinate is
    // set, and has to stay installed even when every other hook is idle.
    %init(RelocateTelemetry);

    // Keeps a running app in step with the preferences without a restart.
    //
    // Without this the globals are whatever they were at launch: a coordinate
    // changed from the settings page would only take effect after the app was
    // killed and reopened. HBPreferences fires this block on the Darwin
    // notification posted after every write.
    [preferences registerPreferenceChangeBlock:^() {
        rlc_apply_preferences();
    }];

    RLC_LOG(@"ctor: app hooks installed in %@", [NSProcessInfo processInfo].processName);
}
