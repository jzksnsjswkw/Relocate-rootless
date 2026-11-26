#import "Preferences.h"
#import <roothide.h>
#import "RLCBinaryPath.h"

@implementation RLCPrefsListController

- (instancetype)init {
    self = [super init];

    if (self) {
        HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
        [prefs registerPreferenceChangeBlock:^() {
            [self reloadSpecifierID:@"enabled" animated:YES];
        }];
    }

    return self;
}

- (id)specifiers {
    if(_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Prefs" target:self];
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    CGRect frame = self.table.bounds;
    frame.origin.y = -frame.size.height;
        
    [self.navigationController.navigationController.navigationBar setShadowImage: [UIImage new]];
    self.navigationController.navigationController.navigationBar.translucent = YES;
}

- (void)resetPrefs:(id)sender {
    HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
    [prefs removeAllObjects];
    
    [self respring:sender];
}

// The links at the bottom of the page.
//
// They used to be HBLinkTableCells, which come from CepheiPrefs and are not
// available here; a PSButtonCell plus an action opens the same URL.
//
// Two rows rather than one, because they answer different questions: where this
// build came from, and where its source is. Pointing a single row at the upstream
// repository left the reader no way to reach the code that actually produced what
// they installed.
//
// The upstream URL's owner is "NepetaDev", not "Nepeta" — the latter is the display
// name, and the wrong one 404s.
- (void)openUpstreamRepo:(id)sender {
    [self rlc_openURL:@"https://github.com/NepetaDev/Relocate"];
}

// This fork's own repository, which is where the iOS 15+ build and the source of
// these settings actually live.
- (void)openGitHub:(id)sender {
    [self rlc_openURL:@"https://github.com/jzksnsjswkw/Relocate-rootless"];
}

- (void)rlc_openURL:(NSString *)string {
    NSURL *url = [NSURL URLWithString:string];
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(openURL:options:completionHandler:)]) {
        [app openURL:url options:@{} completionHandler:nil];
    } else {
        [app openURL:url];
    }
}

- (void)respring:(id)sender {
    NSTask *t = [[NSTask alloc] init];
    [t setLaunchPath:RLCBinaryPath(@"/usr/bin/killall")];
    [t setArguments:[NSArray arrayWithObjects:@"backboardd", nil]];
    [t launch];
}
@end