#import "RLCAppListController.h"
#import "RLCLocalize.h"
#import "RLCAppSettingsController.h"
#import "RLCConfiguredSection.h"

@interface RLCAppListController ()
// Fingerprint of the per-app modes as they were when the list was last built.
@property (nonatomic, copy) NSString *rlcBuiltFingerprint;
@end

@implementation RLCAppListController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.subcontrollerClass = [RLCAppSettingsController class];
    }
    return self;
}

- (void)prepareForPopulatingSections {
    [super prepareForPopulatingSections];
    self.alphabeticIndexingEnabled = YES;
    // The row's second line shows the app's current mode, not its identifier.
    self.showIdentifiersAsSubtitle = NO;
}

#pragma mark - Refresh

// Rebuilds the list when returning from an app's settings page.
//
// The base class caches aggressively: -specifiers only constructs when _specifiers
// is nil, and -reloadApplications clears _allSpecifiers but not _specifiers. After
// the grouping in this file runs, _specifiers holds the letter-grouped array, so a
// plain reload would keep showing the old grouping - an app switched to "override"
// would stay in its letter bucket and out of the star until the whole controller
// was rebuilt by leaving and re-entering the screen.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Rebuilding is what makes the star group correct, but it also discards the
    // scroll position and reloads every icon, which is a visible stall on a list
    // this size. So it only happens when the modes actually changed; a plain
    // back-and-forth with no edits keeps the list as it was.
    NSString *fingerprint = RLCApplicationModesFingerprint();
    if (self.rlcBuiltFingerprint && [self.rlcBuiltFingerprint isEqualToString:fingerprint]) {
        return;
    }
    self.rlcBuiltFingerprint = fingerprint;

    [self setValue:nil forKey:@"_specifiers"];
    [self setValue:nil forKey:@"_allSpecifiers"];
    [self setValue:nil forKey:@"_specifiersByLetter"];
    [self reloadSpecifiers];
}

#pragma mark - Grouping

// A single section, on purpose.
//
// AltList disables alphabetic indexing outright when a controller has more than
// one section:
//
//   - (void)setAlphabeticIndexingEnabled:(BOOL)enabled {
//       if(_applicationSections.count == 1) { _alphabeticIndexingEnabled = enabled; return; }
//       _alphabeticIndexingEnabled = NO;
//   }
//
// Two sections - "configured" and "everything else" - cost the index bar, and the
// index bar is worth more on a several-hundred-row list. Grouping is therefore
// done below by rewriting which letter bucket an app lands in, which keeps the
// framework's own path intact.

// Apps with a stored setting go into a bucket of their own, sorted before A.
//
// The bucket key is arbitrary: grouping here is just a dictionary lookup on this
// string, and specifiersGroupedByLetters below decides the display order.
static NSString *const kRLCConfiguredBucket = @"0configured";

- (void)populateSpecifiersByLetter {
    NSDictionary *buckets = [self valueForKey:@"_specifiersByLetter"];
    (void)buckets;

    [super populateSpecifiersByLetter];

    NSMutableDictionary *byLetter = [self valueForKey:@"_specifiersByLetter"];
    if (![byLetter isKindOfClass:[NSMutableDictionary class]]) return;

    // Walk the app rows the superclass just bucketed and pull out the configured
    // ones. Rows are identified by their applicationIdentifier property, which is
    // what createSpecifierForApplicationProxy sets.
    NSMutableArray *configured = [NSMutableArray array];
    for (NSString *key in [byLetter allKeys]) {
        NSMutableArray *row = byLetter[key];
        if (![row isKindOfClass:[NSMutableArray class]]) continue;

        NSMutableArray *remaining = [NSMutableArray arrayWithCapacity:row.count];
        for (PSSpecifier *specifier in row) {
            NSString *identifier = [specifier propertyForKey:@"applicationIdentifier"];
            if (identifier.length && RLCApplicationHasStoredSetting(identifier)) {
                [configured addObject:specifier];
            } else {
                [remaining addObject:specifier];
            }
        }

        if (remaining.count) byLetter[key] = remaining;
        else [byLetter removeObjectForKey:key];
    }

    if (configured.count) byLetter[kRLCConfiguredBucket] = configured;
}

- (NSMutableArray *)specifiersGroupedByLetters {
    BOOL firstSpecifier = YES;
    NSMutableArray *grouped = [NSMutableArray array];

    // The configured bucket leads, labelled with a star so it reads as its own
    // group rather than as a misplaced letter.
    NSArray *configured = [self valueForKey:@"_specifiersByLetter"][kRLCConfiguredBucket];
    if (configured.count) {
        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        group.name = @"★";
        [group setProperty:@YES forKey:@"isLetterSection"];
        [grouped addObject:group];
        [grouped addObjectsFromArray:configured];
        firstSpecifier = NO;
    }

    for (char c = 'A'; c <= 'Z' + 1; c++) {
        NSString *key = (c == 'Z' + 1) ? @"#" : [NSString stringWithFormat:@"%c", c];

        NSArray *row = [self valueForKey:@"_specifiersByLetter"][key];
        if (!row.count) continue;

        PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
        if (firstSpecifier && self.hideAlphabeticSectionHeaders && configured.count == 0) {
            group.name = [self localizedStringForString:@"Applications"];
            [group setProperty:@YES forKey:@"isFirstLetterSection"];
        } else {
            group.name = key;
            [group setProperty:@YES forKey:@"isLetterSection"];
        }
        [grouped addObject:group];
        [grouped addObjectsFromArray:row];
        firstSpecifier = NO;
    }

    return grouped;
}

// The index bar mirrors the buckets the grouping above produced.
//
// This is rebuilt rather than taken from super: the parent builds its titles by
// listing the bucket keys verbatim, so the internal bucket name would appear in the
// bar as a second, unreadable entry next to the star.
- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    if (!self.alphabeticIndexingEnabled) return nil;

    NSDictionary *byLetter = [self valueForKey:@"_specifiersByLetter"];
    if (![byLetter isKindOfClass:[NSDictionary class]]) return nil;

    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    if (byLetter[kRLCConfiguredBucket]) [titles addObject:@"★"];

    for (char c = 'A'; c <= 'Z'; c++) {
        NSString *key = [NSString stringWithFormat:@"%c", c];
        if (byLetter[key]) [titles addObject:key];
    }

    // Apps whose names do not start with a letter sort last.
    if (byLetter[@"#"]) [titles addObject:@"#"];

    return titles;
}

// Tapping a title jumps to the section it labels.
//
// The parent does not implement this, so the table view's default applies: title
// number n means section n. Because the star occupies index 0 and every letter
// follows it, that default lands one section early for every letter - hence the
// shift by one here.
- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title
                atIndex:(NSInteger)index {
    if (self.alphabeticIndexingEnabled &&
        [[self valueForKey:@"_specifiersByLetter"] isKindOfClass:[NSDictionary class]]) {
        if ([title isEqualToString:@"★"]) return 0;
        return index;
    }

    return [super tableView:tableView sectionForSectionIndexTitle:title atIndex:index];
}

#pragma mark - Selection

// Second line of each row: which mode this app is currently in, so the list is
// scannable without opening every app.
// Hand the app identifier to the settings page, then let the base class push it.
// Doing it here means the page never has to ask AltList and never renders before
// it knows which app it is editing.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *appID = [self _rlcApplicationIDAtIndexPath:indexPath];
    if (appID.length) {
        [RLCAppSettingsController setNextApplicationID:appID];
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// Which app a tapped row belongs to.
//
// The cell is the source of truth, not an index into the controller's specifier
// array: once the search is filtering, those two stop agreeing, and indexing would
// open whichever app happens to sit at that row of the unfiltered list. PSTableCell
// carries the specifier it was configured with, so reading it from the cell is
// correct in both the filtered and unfiltered case.
- (NSString *)_rlcApplicationIDAtIndexPath:(NSIndexPath *)indexPath {
    @try {
        UITableViewCell *cell = [self.table cellForRowAtIndexPath:indexPath];
        if ([cell respondsToSelector:@selector(specifier)]) {
            PSSpecifier *cellSpecifier = [(PSTableCell *)cell specifier];
            NSString *identifier = [cellSpecifier propertyForKey:@"applicationIdentifier"];
            if (identifier.length) return identifier;
            NSString *key = [cellSpecifier propertyForKey:@"key"];
            if (key.length) return key;
        }

        // Fallback for a row whose cell is not on screen yet (only reachable if a
        // selection is replayed programmatically).
        PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
        NSString *identifier = [specifier propertyForKey:@"applicationIdentifier"];
        if (identifier.length) return identifier;
        return [specifier propertyForKey:@"key"];
    } @catch (NSException *e) {
        return nil;
    }
}

- (NSString *)previewStringForApplicationWithIdentifier:(NSString *)applicationID {
    HBPreferences *prefs = [[HBPreferences alloc] initWithIdentifier:@"com.jzksnsjswkw.relocate"];
    NSNumber *stored = [prefs objectForKey:
                        [NSString stringWithFormat:@"App_%@_Enabled", applicationID]];
    switch (stored.intValue) {
        case 1:  return RLCLocalized(@"MODE_OVERRIDE");
        case 2:  return RLCLocalized(@"MODE_USE_REAL");
        default: return RLCLocalized(@"MODE_DEFAULT");
    }
}

@end
