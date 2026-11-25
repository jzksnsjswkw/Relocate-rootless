// RLCChinaCoords.m - see RLCChinaCoords.h.

#import "RLCChinaCoords.h"
#import <math.h>

// Krasovsky 1940 ellipsoid, the one GCJ-02 is defined against.
static const double kA = 6378245.0;
static const double kEE = 0.00669342162296594323;

BOOL RLCIsInsideChina(CLLocationCoordinate2D c) {
    // The rectangle the offset applies to. Hong Kong, Macau and Taiwan are
    // excluded because their maps are not offset.
    if (c.longitude < 72.004 || c.longitude > 137.8347) return NO;
    if (c.latitude < 0.8293 || c.latitude > 55.8271) return NO;
    return YES;
}

static double rlc_transformLat(double x, double y) {
    double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y
               + 0.2 * sqrt(fabs(x));
    ret += (20.0 * sin(6.0 * x * M_PI) + 20.0 * sin(2.0 * x * M_PI)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * M_PI) + 40.0 * sin(y / 3.0 * M_PI)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * M_PI) + 320.0 * sin(y * M_PI / 30.0)) * 2.0 / 3.0;
    return ret;
}

static double rlc_transformLon(double x, double y) {
    double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y
               + 0.1 * sqrt(fabs(x));
    ret += (20.0 * sin(6.0 * x * M_PI) + 20.0 * sin(2.0 * x * M_PI)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * M_PI) + 40.0 * sin(x / 3.0 * M_PI)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * M_PI) + 300.0 * sin(x / 30.0 * M_PI)) * 2.0 / 3.0;
    return ret;
}

/// The forward offset, in degrees, for a WGS-84 point.
static void rlc_delta(double lat, double lon, double *dLat, double *dLon) {
    double radLat = lat / 180.0 * M_PI;
    double magic = sin(radLat);
    magic = 1 - kEE * magic * magic;
    double sqrtMagic = sqrt(magic);

    *dLat = (rlc_transformLat(lon - 105.0, lat - 35.0) * 180.0)
          / ((kA * (1 - kEE)) / (magic * sqrtMagic) * M_PI);
    *dLon = (rlc_transformLon(lon - 105.0, lat - 35.0) * 180.0)
          / (kA / sqrtMagic * cos(radLat) * M_PI);
}

CLLocationCoordinate2D RLCWGS84ToGCJ02(CLLocationCoordinate2D wgs) {
    if (!RLCIsInsideChina(wgs)) return wgs;
    double dLat, dLon;
    rlc_delta(wgs.latitude, wgs.longitude, &dLat, &dLon);
    return CLLocationCoordinate2DMake(wgs.latitude + dLat, wgs.longitude + dLon);
}

CLLocationCoordinate2D RLCGCJ02ToWGS84(CLLocationCoordinate2D gcj) {
    if (!RLCIsInsideChina(gcj)) return gcj;

    // GCJ-02 has no closed-form inverse. Two-step iteration converges to well
    // under a metre, which is far below the accuracy of anything downstream.
    double lat = gcj.latitude, lon = gcj.longitude;
    for (int i = 0; i < 3; i++) {
        double dLat, dLon;
        rlc_delta(lat, lon, &dLat, &dLon);
        lat = gcj.latitude - dLat;
        lon = gcj.longitude - dLon;
    }
    return CLLocationCoordinate2DMake(lat, lon);
}
