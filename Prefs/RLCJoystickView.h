#import <UIKit/UIKit.h>

// A thumbstick drawn over the map, for nudging the pin.
//
// A plain UIView, not a UIWindow. The tweak's own stick is a window because it has
// to float over another app's interface; here there is only one screen and this
// view lives inside it. Reusing the window version meant adding a UIWindow as a
// subview, which UIKit does not support cleanly: it drew once, then ignored
// -removeFromSuperview and stayed on screen.
//
// It reports displacement rather than a position, in the same units the tweak
// uses, so the caller decides what to move.
@interface RLCJoystickView : UIView

// Offset from centre, normalised to the ring's radius: -1 to 1 on each axis, zero
// when released.
@property (nonatomic, assign, readonly) CGFloat inputX;
@property (nonatomic, assign, readonly) CGFloat inputY;

// Called when the thumb returns to centre, so the caller can commit the position
// the stick finished on.
@property (nonatomic, copy) void (^onRelease)(void);

-(instancetype)initWithFrame:(CGRect)frame;

@end
