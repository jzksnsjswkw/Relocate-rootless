#import "RLCJoystickView.h"
#import <AudioToolbox/AudioToolbox.h>

@interface RLCJoystickView ()
// Redeclared read-write so the pan handler can assign through the property rather
// than touching the synthesised ivar.
@property (nonatomic, assign, readwrite) CGFloat inputX;
@property (nonatomic, assign, readwrite) CGFloat inputY;
@property (nonatomic, retain) CAShapeLayer *ringLayer;
@property (nonatomic, retain) CAShapeLayer *thumbLayer;
@property (nonatomic, assign) CGPoint ringCenter;
@property (nonatomic, assign) CGFloat ringRadius;
@property (nonatomic, assign) CGFloat thumbRadius;
@property (nonatomic, retain) UIPanGestureRecognizer *pan;
@end

@implementation RLCJoystickView

-(instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    self.backgroundColor = [UIColor clearColor];
    self.userInteractionEnabled = YES;
    // Only the ring is opaque to touches: taps elsewhere on the map still reach it.
    self.opaque = NO;

    self.ringRadius = 75;
    self.thumbRadius = 22;

    self.ringLayer = [CAShapeLayer layer];
    self.ringLayer.strokeColor = [[UIColor colorWithWhite:1 alpha:0.9] CGColor];
    self.ringLayer.fillColor = [[UIColor colorWithWhite:0 alpha:0.15] CGColor];
    self.ringLayer.lineWidth = 2;
    [self.layer addSublayer:self.ringLayer];

    self.thumbLayer = [CAShapeLayer layer];
    self.thumbLayer.strokeColor = [[UIColor colorWithWhite:0 alpha:0.2] CGColor];
    self.thumbLayer.fillColor = [[UIColor whiteColor] CGColor];
    self.thumbLayer.lineWidth = 1;
    [self.layer addSublayer:self.thumbLayer];

    self.pan = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                       action:@selector(handlePan:)];
    [self addGestureRecognizer:self.pan];

    return self;
}

-(void)layoutSubviews {
    [super layoutSubviews];

    // Anchored to the bottom-right, where the map has no other controls.
    self.ringCenter = CGPointMake(CGRectGetWidth(self.bounds) - 105,
                                  CGRectGetHeight(self.bounds) - 115);

    self.ringLayer.path = [[UIBezierPath bezierPathWithArcCenter:self.ringCenter
                                                         radius:self.ringRadius
                                                     startAngle:0
                                                       endAngle:M_PI * 2
                                                      clockwise:YES] CGPath];
    [self moveThumbToCenter];
}

-(void)moveThumbToCenter {
    self.thumbLayer.path = [[UIBezierPath bezierPathWithArcCenter:self.ringCenter
                                                          radius:self.thumbRadius
                                                      startAngle:0
                                                        endAngle:M_PI * 2
                                                       clockwise:YES] CGPath];
}

-(UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // Outside the ring the map keeps the touch; without this the whole screen would
    // be covered by an invisible view.
    CGFloat dx = point.x - self.ringCenter.x;
    CGFloat dy = point.y - self.ringCenter.y;
    BOOL inside = (dx * dx + dy * dy) <= (self.ringRadius + 20) * (self.ringRadius + 20);
    return inside ? self : nil;
}

-(void)handlePan:(UIPanGestureRecognizer *)recognizer {
    CGPoint point = [recognizer locationInView:self];
    CGFloat dx = point.x - self.ringCenter.x;
    CGFloat dy = point.y - self.ringCenter.y;
    CGFloat distance = sqrt(dx * dx + dy * dy);

    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            if (distance > self.ringRadius) {
                // Clamped to the rim, so pushing past it still gives full speed
                // instead of losing the gesture.
                dx = dx / distance * self.ringRadius;
                dy = dy / distance * self.ringRadius;
                distance = self.ringRadius;
            }

            self.thumbLayer.path = [[UIBezierPath
                bezierPathWithArcCenter:CGPointMake(self.ringCenter.x + dx,
                                                   self.ringCenter.y + dy)
                                 radius:self.thumbRadius
                             startAngle:0
                               endAngle:M_PI * 2
                              clockwise:YES] CGPath];

            // Normalised, and y flipped: screen coordinates grow downward, while a
            // push up has to mean north.
            _inputX = self.ringRadius > 0 ? dx / self.ringRadius : 0;
            _inputY = self.ringRadius > 0 ? -dy / self.ringRadius : 0;
            break;
        }

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            [self moveThumbToCenter];
            _inputX = 0;
            _inputY = 0;
            if (self.onRelease) self.onRelease();
            break;
        }

        default:
            break;
    }
}

@end
