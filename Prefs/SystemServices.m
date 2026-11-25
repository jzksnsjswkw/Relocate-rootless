#import "SystemServices.h"
#import <roothide.h>
#import "RLCBinaryPath.h"

@implementation RLCSystemServicesListController

- (id)specifiers {
    if(_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"SystemServices" target:self];
    }
    return _specifiers;
}

// Restarts a launchd job and waits for it to come back.
//
// Killing alone is not enough. These daemons are EnablePressuredExit, so launchd
// does not respawn them until something asks - which is why the position used to
// take minutes to take effect: the new dylib was already installed, but the old
// process kept running with the old one until the system happened to start a
// fresh copy.
//
// kickstart --kill does both halves in one call: terminate, then start again
// immediately, so the replacement happens while the user is still on this page.
static void RLCRestartJob(NSString *label) {
    NSTask *t = [[NSTask alloc] init];

    // launchctl is a system binary, not a jailbreak one: it lives at
    // /usr/bin/launchctl on every layout, so jbroot() must not be applied here.
    t.launchPath = @"/usr/bin/launchctl";
    t.arguments = @[ @"kickstart", @"-k", [@"system/" stringByAppendingString:label] ];
    @try {
        [t launch];
    } @catch (NSException *e) {
        NSLog(@"[Relocate] restart %@ failed: %@", label, e);
    }
}

- (void)restartFMF:(id)sender {
    RLCRestartJob(@"com.apple.icloud.fmfd");
    RLCRestartJob(@"com.apple.icloud.fmflocatord");
}

- (void)restartFMI:(id)sender {
    RLCRestartJob(@"com.apple.icloud.findmydeviced");
}

@end