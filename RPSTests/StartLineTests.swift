//
//  StartLineTests.swift
//  RPSTests
//
//  Mirrors the reference app's start-line.util.spec.ts, including the case
//  that caught the real bug: the favoured end must be resolved by distance
//  to the first mark, not by the sign of the off-square angle.
//

import Testing
@testable import RPS

private typealias LatLon = GeoMath.LatLon

// A start line somewhere in Massachusetts Bay, built by projection rather
// than by hand so the geometry is exactly what each case claims it is.
private let MID = LatLon(lat: 42.48, lon: -70.82)

/// Builds a line of `lengthM` metres, rotated `biasDeg` off square to a wind
/// blowing from `windDir`, with a windward mark a mile upwind.
private func scenario(windDir: Double, biasDeg: Double, lengthM: Double = 200) -> (pin: LatLon, committee: LatLon, firstMark: LatLon) {
    let halfNm = lengthM / 2 / 1852
    let bearing = windDir + 90 + biasDeg
    let committee = GeoMath.destinationPoint(lat: MID.lat, lon: MID.lon, bearingDeg: bearing, distNm: halfNm)
    let pin = GeoMath.destinationPoint(lat: MID.lat, lon: MID.lon, bearingDeg: bearing + 180, distNm: halfNm)
    let firstMark = GeoMath.destinationPoint(lat: MID.lat, lon: MID.lon, bearingDeg: windDir, distNm: 1)
    return (pin, committee, firstMark)
}

struct ComputeLineBiasTests {

    @Test func callsASquareLineSquare() {
        let s = scenario(windDir: 0, biasDeg: 0)
        let bias = StartLine.computeLineBias(pin: s.pin, committee: s.committee, firstMark: s.firstMark)
        #expect(bias.favoured == .square)
        // Not exactly zero: projecting the two ends in opposite directions
        // from the midpoint follows great circles, which converge slightly.
        #expect(abs(bias.biasDeg) < 0.01)
        #expect(bias.advantageM < 1)
    }

    @Test func measuresLineLengthAndBearing() {
        let s = scenario(windDir: 0, biasDeg: 0, lengthM: 240)
        let bias = StartLine.computeLineBias(pin: s.pin, committee: s.committee, firstMark: s.firstMark)
        #expect(abs(bias.lengthM - 240) < 1)
        #expect(abs(bias.lineBearing - 90) < 0.1)
        #expect(abs(bias.windDirTrue - 0) < 0.1)
    }

    // The end that is favoured is the end that is further upwind, so the
    // sign convention is checked against plain distance-to-the-mark rather
    // than against itself.
    @Test func favoursWhicheverEndIsActuallyCloserToTheFirstMark() {
        for windDir in [0.0, 45, 137, 250, 350] {
            for biasDeg in [-25.0, -8, 8, 25] {
                let s = scenario(windDir: windDir, biasDeg: biasDeg)
                let bias = StartLine.computeLineBias(pin: s.pin, committee: s.committee, firstMark: s.firstMark)
                let pinDist = GeoMath.haversineNm(lat1: s.pin.lat, lon1: s.pin.lon, lat2: s.firstMark.lat, lon2: s.firstMark.lon)
                let cmteDist = GeoMath.haversineNm(lat1: s.committee.lat, lon1: s.committee.lon, lat2: s.firstMark.lat, lon2: s.firstMark.lon)
                let closer: StartLine.FavouredEnd = pinDist < cmteDist ? .pin : .committee
                #expect(bias.favoured == closer)
                #expect(abs(bias.biasDeg - biasDeg) < 0.5)
            }
        }
    }

    @Test func pricesTheAdvantageAtLengthTimesSinBias() {
        let s = scenario(windDir: 20, biasDeg: 15, lengthM: 300)
        let bias = StartLine.computeLineBias(pin: s.pin, committee: s.committee, firstMark: s.firstMark)
        let expected = 300 * sin(15 * Double.pi / 180)
        #expect(abs(bias.advantageM - expected) < 1)
    }

    @Test func neverReportsABiasBeyond90Degrees() {
        let s = scenario(windDir: 0, biasDeg: 12)
        // Pinging the ends the other way round describes the same line.
        let flipped = StartLine.computeLineBias(pin: s.committee, committee: s.pin, firstMark: s.firstMark)
        #expect(abs(flipped.biasDeg) <= 90)
        let original = StartLine.computeLineBias(pin: s.pin, committee: s.committee, firstMark: s.firstMark)
        #expect(abs(flipped.advantageM - original.advantageM) < 0.5)
    }

    // Which end gets pinged first is arbitrary and must not change the
    // answer. An earlier version derived the favoured end from the sign of
    // the angle off square, which cannot work: folding the angle onto the
    // line maps the two ends onto each other.
    @Test func namesTheSamePhysicalEndWhicheverEndWasPingedFirst() {
        for windDir in [0.0, 63, 157, 210, 305] {
            for biasDeg in [-30.0, -10, 10, 30] {
                let s = scenario(windDir: windDir, biasDeg: biasDeg)
                let asPinged = StartLine.computeLineBias(pin: s.pin, committee: s.committee, firstMark: s.firstMark)
                let swapped = StartLine.computeLineBias(pin: s.committee, committee: s.pin, firstMark: s.firstMark)

                let expectedSwappedFavoured: StartLine.FavouredEnd = asPinged.favoured == .pin ? .committee : .pin
                #expect(swapped.favoured == expectedSwappedFavoured)
                #expect(abs(swapped.biasDeg - (-asPinged.biasDeg)) < 0.5)
                #expect(abs(swapped.advantageM - asPinged.advantageM) < 0.5)
            }
        }
    }

    // The case that caught the bug on the water: a line running due
    // east-west with the mark to the south-south-east. The east (boat) end
    // is plainly closer to the mark, and that is the end that must be named.
    @Test func favoursTheEndNearerTheMarkOnARealEastWestLine() {
        let committee = LatLon(lat: 42.479, lon: -70.82) // east end
        let pin = LatLon(lat: 42.479, lon: -70.8218) // west end
        let firstMark = LatLon(lat: 42.2789, lon: -70.7581) // Harding Ledge, SSE
        let bias = StartLine.computeLineBias(pin: pin, committee: committee, firstMark: firstMark)
        #expect(bias.favoured == .committee)
        #expect(bias.biasDeg < 0)
        #expect(abs(bias.lengthM - 148) < 1)
    }
}

struct ComputeLineApproachTests {

    let s = scenario(windDir: 0, biasDeg: 0)

    @Test func isPositiveOnPreStartSideAndNegativeOnceOver() {
        // The mark is due north, so south of the line is the pre-start side.
        let below = GeoMath.destinationPoint(lat: MID.lat, lon: MID.lon, bearingDeg: 180, distNm: 50 / 1852)
        let above = GeoMath.destinationPoint(lat: MID.lat, lon: MID.lon, bearingDeg: 0, distNm: 50 / 1852)
        let belowApproach = StartLine.computeLineApproach(pin: s.pin, committee: s.committee, firstMark: s.firstMark, boat: below, speedKts: nil)
        let aboveApproach = StartLine.computeLineApproach(pin: s.pin, committee: s.committee, firstMark: s.firstMark, boat: above, speedKts: nil)
        #expect(abs(belowApproach.distanceM - 50) < 1)
        #expect(abs(aboveApproach.distanceM - (-50)) < 1)
        #expect(aboveApproach.over)
    }

    @Test func readsTheSameWhicheverEndWasPingedFirst() {
        let boat = GeoMath.destinationPoint(lat: MID.lat, lon: MID.lon, bearingDeg: 180, distNm: 80 / 1852)
        let a = StartLine.computeLineApproach(pin: s.pin, committee: s.committee, firstMark: s.firstMark, boat: boat, speedKts: nil).distanceM
        let b = StartLine.computeLineApproach(pin: s.committee, committee: s.pin, firstMark: s.firstMark, boat: boat, speedKts: nil).distanceM
        #expect(abs(a - b) < 0.01)
        #expect(a > 0)
    }

    @Test func convertsTheGapToSecondsOfBurnTime() {
        let boat = GeoMath.destinationPoint(lat: MID.lat, lon: MID.lon, bearingDeg: 180, distNm: 100 / 1852)
        // 5 knots is 2.572 m/s, so 100m is a shade under 39 seconds.
        let approach = StartLine.computeLineApproach(pin: s.pin, committee: s.committee, firstMark: s.firstMark, boat: boat, speedKts: 5)
        let expected = 100 / (5 * 0.514444)
        #expect(abs((approach.timeToLineSec ?? -1) - expected) < 1)
    }

    @Test func givesNoBurnTimeWhenStopped() {
        let boat = GeoMath.destinationPoint(lat: MID.lat, lon: MID.lon, bearingDeg: 180, distNm: 100 / 1852)
        #expect(StartLine.computeLineApproach(pin: s.pin, committee: s.committee, firstMark: s.firstMark, boat: boat, speedKts: 0.05).timeToLineSec == nil)
        #expect(StartLine.computeLineApproach(pin: s.pin, committee: s.committee, firstMark: s.firstMark, boat: boat, speedKts: nil).timeToLineSec == nil)
    }
}
