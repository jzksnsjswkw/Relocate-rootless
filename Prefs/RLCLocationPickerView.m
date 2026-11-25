#import "RLCLocationPickerView.h"
#import "RLCLocalize.h"
#import "RLCLocationPickerViewController.h"

@implementation RLCLocationPickerView

-(id)initWithFrame:(CGRect)frame controller:(UIViewController*)controller {
    self = [super initWithFrame:frame];

    self.mapView = [[MKMapView alloc] initWithFrame:frame];
    self.mapView.delegate = self;

    self.longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(movePin:)];
    [self.mapView addGestureRecognizer:self.longPressRecognizer];

    [self addSubview:self.mapView];

    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.mapView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

-(void)createPinAt:(CLLocationCoordinate2D)coord {
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coord,
                                                                  RLC_PICKER_SPAN_METERS,
                                                                  RLC_PICKER_SPAN_METERS);

    self.pin = [[MKPointAnnotation alloc] init];
    [self.pin setCoordinate:coord];
    [self.pin setTitle:RLCLocalized(@"SELECTED_LOCATION")];

    [self.mapView setRegion:region];
    [self.mapView addAnnotation:self.pin];
}

-(void)hideCallouts {
    for (id annotation in self.mapView.selectedAnnotations) {
        [self.mapView deselectAnnotation:annotation animated:YES];
    }
}

-(void)mapView:(MKMapView *)mapView regionWillChangeAnimated:(BOOL)animated {
    [self hideCallouts];
}


-(MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    MKMarkerAnnotationView *view = (id)[mapView dequeueReusableAnnotationViewWithIdentifier:@"annotation"];
    if (view) {
        view.annotation = annotation;
    } else {
        view = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"annotation"];
        view.canShowCallout = true;
        
        if (annotation != self.pin) return view;
        
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(0, 0, 50, 40);

        [button setBackgroundColor:self.tintColor];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [button setTitle:@"★" forState:UIControlStateNormal];
        [button addTarget:self.nextResponder action:@selector(favorite:) forControlEvents:UIControlEventPrimaryActionTriggered];

        view.rightCalloutAccessoryView = button;
    }

    return view;
}

-(void)movePin:(UIGestureRecognizer *)recognizer {
    // Once per gesture: the long press reports Began, Changed and Ended, and only
    // the last one means "this is where it stays".
    if (recognizer.state == UIGestureRecognizerStateEnded) {
        [self.pinGestureTarget pinDidSettle];
        return;
    }

    [self hideCallouts];

    CGPoint point = [recognizer locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:point toCoordinateFromView:self.mapView];
    if (!self.pin) [self createPinAt:coord];
    else [self.pin setCoordinate:coord];
    [self.pin setTitle:RLCLocalized(@"SELECTED_LOCATION")];
}

@end
