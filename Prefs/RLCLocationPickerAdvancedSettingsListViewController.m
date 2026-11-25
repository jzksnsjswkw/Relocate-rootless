#import "RLCLocationPickerAdvancedSettingsListViewController.h"
#import "RLCLocationPickerViewController.h"

@implementation RLCLocationPickerAdvancedSettingsListViewController

- (id)specifiers {
    if(_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"AdvancedSettings" target:self];
    }
    return _specifiers;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    // A plain sheet: the map behind would otherwise show through the rows.
    [self setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
}

-(UITableView *)table {
    return _table;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    if ([specifier propertyForKey:@"defaults"]) return [super readPreferenceValue:specifier];
    if (![specifier propertyForKey:@"key"]) return [specifier propertyForKey:@"default"];

    RLCLocationPickerViewController *parent = self.parent;
    if (parent && parent.dictionary && parent.dictionary[[specifier propertyForKey:@"key"]]) {
        return parent.dictionary[[specifier propertyForKey:@"key"]];
    }

    return [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (![specifier propertyForKey:@"key"]) return;
    if ([specifier propertyForKey:@"defaults"]) [super setPreferenceValue:value specifier:specifier];

    RLCLocationPickerViewController *parent = self.parent;

    if ([[specifier propertyForKey:@"key"] isEqualToString:@"MapType"]) {
        switch ([value intValue]) {
            case 1:
                parent.lpView.mapView.mapType = MKMapTypeSatellite;
                break;
            case 2:
                parent.lpView.mapView.mapType = MKMapTypeHybrid;
                break;
            default:
                parent.lpView.mapView.mapType = MKMapTypeStandard;
        }
        return;
    }

    if (parent && parent.dictionary) {
        parent.dictionary[[specifier propertyForKey:@"key"]] = value;
    }
}

@end
