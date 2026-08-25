//
//  GeoMath.swift
//  RPS
//
//  Pure geo math, ported from the reference web app's `geo.util.ts`:
//  great-circle distance, initial bearing, destination-point projection,
//  true/magnetic conversion, cross-track distance, and midpoint. This is the
//  base layer every other piece of sailing math in the app builds on.
//

import Foundation

/// Pure, dependency-free geo math on lat/lon in degrees.
enum GeoMath {

    static let earthRadiusNm = 3440.065

    private static func toRad(_ d: Double) -> Double { d * .pi / 180 }
    private static func toDeg(_ r: Double) -> Double { r * 180 / .pi }

    /// Great-circle distance between two lat/lon points, in nautical miles.
    static func haversineNm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = toRad(lat1)
        let phi2 = toRad(lat2)
        let dPhi = toRad(lat2 - lat1)
        let dLambda = toRad(lon2 - lon1)
        let a = pow(sin(dPhi / 2), 2) + cos(phi1) * cos(phi2) * pow(sin(dLambda / 2), 2)
        return 2 * earthRadiusNm * asin(sqrt(a))
    }

    /// Initial (true) bearing from point 1 to point 2, in degrees [0, 360).
    static func initialBearing(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = toRad(lat1)
        let phi2 = toRad(lat2)
        let dLambda = toRad(lon2 - lon1)
        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        return (toDeg(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
    }

    struct LatLon: Equatable {
        var lat: Double
        var lon: Double
    }

    /// Projects a destination point from a start point, bearing, and distance (nm).
    static func destinationPoint(lat: Double, lon: Double, bearingDeg: Double, distNm: Double) -> LatLon {
        let d = distNm / earthRadiusNm
        let brg = toRad(bearingDeg)
        let phi1 = toRad(lat)
        let lam1 = toRad(lon)
        let phi2 = asin(sin(phi1) * cos(d) + cos(phi1) * sin(d) * cos(brg))
        let lam2 = lam1 + atan2(sin(brg) * sin(d) * cos(phi1), cos(d) - sin(phi1) * sin(phi2))
        return LatLon(lat: toDeg(phi2), lon: toDeg(lam2))
    }

    /// True/magnetic heading converted by a variation (degrees), wrapped to [0, 360).
    static func applyVariation(trueHeadingDeg: Double, variationDeg: Double) -> Double {
        ((trueHeadingDeg - variationDeg).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    /// Formats a heading as a 3-digit degree string, e.g. "047°".
    static func fmtHeading(_ deg: Double) -> String {
        let rounded = Int(deg.rounded())
        return String(format: "%03d°", rounded)
    }

    /// Difference between two compass bearings, normalised to -180..180.
    /// Negative means `target` lies to port of `from`.
    static func signedAngleDiff(target: Double, from: Double) -> Double {
        (((target - from).truncatingRemainder(dividingBy: 360)) + 540)
            .truncatingRemainder(dividingBy: 360) - 180
    }

    /// Signed cross-track distance from a point to the great circle through
    /// `from` -> `to`, in metres. Positive when the point lies to the right of
    /// that line looking from `from` towards `to`.
    ///
    /// This is the standard cross-track formula rather than a flat-earth
    /// approximation. A start line is only a few hundred metres long so the two
    /// agree to well under a metre here, but the exact form costs nothing and
    /// can't quietly go wrong if it's ever used over a longer baseline.
    static func crossTrackM(
        fromLat: Double, fromLon: Double,
        toLat: Double, toLon: Double,
        pointLat: Double, pointLon: Double
    ) -> Double {
        let d13 = haversineNm(lat1: fromLat, lon1: fromLon, lat2: pointLat, lon2: pointLon) / earthRadiusNm
        let th13 = toRad(initialBearing(lat1: fromLat, lon1: fromLon, lat2: pointLat, lon2: pointLon))
        let th12 = toRad(initialBearing(lat1: fromLat, lon1: fromLon, lat2: toLat, lon2: toLon))
        return asin(sin(d13) * sin(th13 - th12)) * earthRadiusNm * 1852
    }

    /// Midpoint of two positions. Adequate to well under a metre over the
    /// length of a start line.
    static func midpoint(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> LatLon {
        let phi1 = toRad(lat1)
        let phi2 = toRad(lat2)
        let dLambda = toRad(lon2 - lon1)
        let bx = cos(phi2) * cos(dLambda)
        let by = cos(phi2) * sin(dLambda)
        let phi3 = atan2(sin(phi1) + sin(phi2), sqrt(pow(cos(phi1) + bx, 2) + by * by))
        let lam3 = toRad(lon1) + atan2(by, cos(phi1) + bx)
        return LatLon(lat: toDeg(phi3), lon: ((toDeg(lam3) + 540).truncatingRemainder(dividingBy: 360)) - 180)
    }
}
