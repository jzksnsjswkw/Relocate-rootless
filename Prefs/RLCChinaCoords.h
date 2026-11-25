// RLCChinaCoords.h - WGS-84 <-> GCJ-02 conversion for the map picker.
//
// The picker's map is the system map. Inside China that map is drawn in GCJ-02
// (the "Mars coordinate" system required by law), so the coordinate a pin lands
// on is GCJ-02. CLLocationManager hands apps WGS-84, and that is what the tweak
// has to inject - a GCJ-02 value written straight through lands the target app
// roughly 100-500 m away from where the user pointed.
//
// So the boundary is here: everything the picker *writes* is converted to
// WGS-84, everything it *reads back* is converted to GCJ-02 for the pin.

#import <CoreLocation/CoreLocation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// GCJ-02 -> WGS-84. Used when saving a pin picked on the (GCJ-02) map.
CLLocationCoordinate2D RLCGCJ02ToWGS84(CLLocationCoordinate2D gcj);

/// WGS-84 -> GCJ-02. Used when showing a stored coordinate on the map.
CLLocationCoordinate2D RLCWGS84ToGCJ02(CLLocationCoordinate2D wgs);

/// Whether a coordinate falls in the area where GCJ-02 applies. Outside it the
/// conversion functions return their input unchanged.
BOOL RLCIsInsideChina(CLLocationCoordinate2D coordinate);

#ifdef __cplusplus
}
#endif
