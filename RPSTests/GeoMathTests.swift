//
//  GeoMathTests.swift
//  RPSTests
//
//  Mirrors the reference app's geo.util.spec.ts.
//

import Testing
@testable import RPS

struct GeoMathTests {

    // Real seeded marks: BYC "A" Tinkers Gong -> "H" Archer Rock.
    let A = GeoMath.LatLon(lat: 42.48187, lon: -70.81444)
    let H = GeoMath.LatLon(lat: 42.51206, lon: -70.82368)

    @Test func haversineComputesPlausibleDistance() {
        let nm = GeoMath.haversineNm(lat1: A.lat, lon1: A.lon, lat2: H.lat, lon2: H.lon)
        // Roughly 2.1nm apart on Massachusetts Bay; a loose bound catches
        // gross regressions without being brittle about the exact float.
        #expect(nm > 1.8)
        #expect(nm < 2.4)
    }

    @Test func haversineIsSymmetricAndZeroForSamePoint() {
        #expect(abs(GeoMath.haversineNm(lat1: A.lat, lon1: A.lon, lat2: A.lat, lon2: A.lon)) < 1e-6)
        let ah = GeoMath.haversineNm(lat1: A.lat, lon1: A.lon, lat2: H.lat, lon2: H.lon)
        let ha = GeoMath.haversineNm(lat1: H.lat, lon1: H.lon, lat2: A.lat, lon2: A.lon)
        #expect(abs(ah - ha) < 1e-9)
    }

    @Test func initialBearingPointsRoughlyNorthWrappingNear360() {
        let brg = GeoMath.initialBearing(lat1: A.lat, lon1: A.lon, lat2: H.lat, lon2: H.lon)
        #expect(brg >= 0)
        #expect(brg < 360)
        // H is north and very slightly west of A, so the bearing wraps just
        // under 360 rather than sitting just above 0.
        #expect(brg > 340)
    }

    @Test func destinationPointRoundTripsWithBearingAndDistance() {
        let brg = GeoMath.initialBearing(lat1: A.lat, lon1: A.lon, lat2: H.lat, lon2: H.lon)
        let dist = GeoMath.haversineNm(lat1: A.lat, lon1: A.lon, lat2: H.lat, lon2: H.lon)
        let dest = GeoMath.destinationPoint(lat: A.lat, lon: A.lon, bearingDeg: brg, distNm: dist)
        #expect(abs(dest.lat - H.lat) < 0.001)
        #expect(abs(dest.lon - H.lon) < 0.001)
    }

    @Test func applyVariationSubtractsAndWraps() {
        #expect(abs(GeoMath.applyVariation(trueHeadingDeg: 10, variationDeg: -14.6) - 24.6) < 1e-6)
        #expect(abs(GeoMath.applyVariation(trueHeadingDeg: 5, variationDeg: 20) - 345) < 1e-6) // wraps below zero
        #expect(abs(GeoMath.applyVariation(trueHeadingDeg: 350, variationDeg: -20) - 10) < 1e-6) // wraps above 360
    }

    @Test func fmtHeadingPadsToThreeDigits() {
        #expect(GeoMath.fmtHeading(7) == "007°")
        #expect(GeoMath.fmtHeading(47.6) == "048°")
        #expect(GeoMath.fmtHeading(180) == "180°")
    }

    @Test func signedAngleDiffIsNegativeToPort() {
        #expect(GeoMath.signedAngleDiff(target: 80, from: 90) == -10)
        #expect(GeoMath.signedAngleDiff(target: 350, from: 10) == -20)
        #expect(GeoMath.signedAngleDiff(target: 10, from: 350) == 20)
    }

    @Test func midpointOfIdenticalPointsIsThatPoint() {
        let mid = GeoMath.midpoint(lat1: A.lat, lon1: A.lon, lat2: A.lat, lon2: A.lon)
        #expect(abs(mid.lat - A.lat) < 1e-6)
        #expect(abs(mid.lon - A.lon) < 1e-6)
    }
}
