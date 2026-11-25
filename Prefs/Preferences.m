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

// The GitHub row used to be an HBLinkTableCell, which comes from CepheiPrefs -
// not available here. A PSButtonCell plus this action opens the same URL.
//
// Points at the original author's repository. The earlier 404 was a wrong owner
// name: "Nepeta" is the display name, "NepetaDev" is the GitHub account.
- (void)openGitHub:(id)sender {
    NSURL *url = [NSURL URLWithString:@"https://github.com/NepetaDev/Relocate"];
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