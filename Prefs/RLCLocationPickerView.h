#import <MapKit/MapKit.h>

// Default zoom for the picker, in metres across.
//
// Matches Locus, which opens at 2000 m: close enough that a street is legible and
// the pin can be placed on a block, wide enough to see the surrounding area.
//
// Metres rather than degrees on purpose. A degree of longitude shrinks with
// latitude, so a fixed degree span is a different real-world width everywhere -
// 0.02 degrees is 2.2 km at the equator and 1.3 km in Beijing.
#define RLC_PICKER_SPAN_METERS 2000

@interface RLCLocationPickerView : UIView <MKMapViewDelegate>

@property (nonatomic, retain) MKMapView *mapView;
@property (nonatomic, retain) MKPointAnnotation *pin;
@property (nonatomic, retain) UILongPressGestureRecognizer *longPressRecognizer;

// Told when the pin stops moving, so the picker can store the position without
// the map knowing anything about preferences.
@property (nonatomic, assign) id pinGestureTarget;

-(void)hideCallouts;
-(void)pinDidSettle;
-(id)initWithFrame:(CGRect)frame controller:(UIViewController*)controller;
-(void)createPinAt:(CLLocationCoordinate2D)coord;

@end
