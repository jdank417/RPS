//
//  CourseLegsTests.swift
//  RPSTests
//
//  Covers course-entry.swift and course-legs.swift: resolved positions,
//  rounding cycling, the twice-around repeat rule, and the leg computation's
//  missing-position / zero-length-leg edge cases — ported from the
//  reference app's course-entry.model.ts and course-legs.util.ts.
//

import Testing
import Foundation
@testable import RPS

private func mark(_ code: String, lat: Double? = nil, lon: Double? = nil, portable: Bool = false, name: String? = nil) -> Mark {
    Mark(
        id: UUID(), markListId: UUID(), code: code, name: name ?? code, govtLight: nil,
        lat: lat, lon: lon, govNumber: nil, portable: portable, notes: nil, displayOrder: 0
    )
}

private func entry(_ uid: Int, _ mark: Mark, overrideLat: Double? = nil, overrideLon: Double? = nil, rounding: Rounding? = nil) -> CourseEntry {
    CourseEntry(uid: uid, mark: mark, overrideLat: overrideLat, overrideLon: overrideLon, rounding: rounding)
}

struct CourseEntryModelTests {

    @Test func resolvedPositionPrefersOverrideOverChartedPosition() {
        let m = mark("A", lat: 1, lon: 2)
        let e = entry(1, m, overrideLat: 5, overrideLon: 6)
        let pos = resolvedPosition(e)
        #expect(pos?.lat == 5)
        #expect(pos?.lon == 6)
    }

    @Test func resolvedPositionFallsBackToChartedPosition() {
        let e = entry(1, mark("A", lat: 1, lon: 2))
        #expect(resolvedPosition(e)?.lat == 1)
    }

    @Test func resolvedPositionIsNilForAnUnplacedPortableMark() {
        let e = entry(1, mark("St", portable: true))
        #expect(resolvedPosition(e) == nil)
    }

    @Test func roundingCyclesStarboardPortThenUnset() {
        #expect(cycleRounding(nil) == .starboard)
        #expect(cycleRounding(.starboard) == .port)
        #expect(cycleRounding(.port) == nil)
    }

    @Test func roundingWordsAreReadable() {
        #expect(roundingWord(.starboard) == "leave to starboard")
        #expect(roundingWord(.port) == "leave to port")
        #expect(roundingWord(nil) == "")
    }
}

struct IsStartEntryTests {
    @Test func explicitStartUidWins() {
        let e = entry(7, mark("A"))
        #expect(isStartEntry(e, index: 3, startUid: 7))
        #expect(!isStartEntry(e, index: 3, startUid: 8))
    }

    @Test func fallsBackToALeadingMarkNamedStart() {
        let e = entry(1, mark("St", name: "Start/Finish"))
        #expect(isStartEntry(e, index: 0, startUid: nil))
        // Only the leading entry qualifies for the name-based fallback.
        #expect(!isStartEntry(e, index: 1, startUid: nil))
    }
}

struct ComputeCourseLegsTests {

    // A small right-triangle-ish course: A -> B -> C, all charted.
    let a = mark("A", lat: 42.480, lon: -70.820)
    let b = mark("B", lat: 42.490, lon: -70.820)
    let c = mark("C", lat: 42.490, lon: -70.810)

    @Test func computesDistanceAndHeadingPerLeg() {
        let course = [entry(1, a), entry(2, b), entry(3, c)]
        let result = computeCourseLegs(course, opts: CourseLegOptions(defaultRounding: nil, twiceAround: false, startUid: nil, variationDeg: 0))

        #expect(result.legs.count == 2)
        #expect(result.legs[0].missing == false)
        #expect(result.legs[0].fromLabel == "A")
        #expect(result.legs[0].toLabel == "B")
        // A -> B is due north.
        #expect(abs((result.legs[0].trueHdg ?? -1) - 0) < 1)
        #expect(result.totalNm > 0)
        #expect(abs(result.totalNm - ((result.legs[0].distNm ?? 0) + (result.legs[1].distNm ?? 0))) < 1e-9)
    }

    @Test func appliesVariationToMagneticHeading() {
        let course = [entry(1, a), entry(2, b)]
        let result = computeCourseLegs(course, opts: CourseLegOptions(defaultRounding: nil, twiceAround: false, startUid: nil, variationDeg: -14.6))
        let leg = result.legs[0]
        #expect(abs((leg.magHdg ?? 0) - GeoMath.applyVariation(trueHeadingDeg: leg.trueHdg ?? 0, variationDeg: -14.6)) < 1e-9)
    }

    @Test func flagsALegToAnUnplacedMarkAsMissingAndExcludesItFromTotal() {
        let unplaced = mark("X", portable: true)
        let course = [entry(1, a), entry(2, unplaced), entry(3, b)]
        let result = computeCourseLegs(course, opts: CourseLegOptions(defaultRounding: nil, twiceAround: false, startUid: nil, variationDeg: 0))

        #expect(result.legs[0].missing == true)
        #expect(result.legs[0].distNm == nil)
        // Leg 2 (unplaced -> b) is also missing, since its "from" has no
        // position either.
        #expect(result.legs[1].missing == true)
        #expect(result.totalNm == 0)
    }

    @Test func treatsAZeroLengthLegAsMissing() {
        let sameSpot = mark("A2", lat: a.lat, lon: a.lon)
        let course = [entry(1, a), entry(2, sameSpot)]
        let result = computeCourseLegs(course, opts: CourseLegOptions(defaultRounding: nil, twiceAround: false, startUid: nil, variationDeg: 0))
        #expect(result.legs[0].missing == true)
    }

    @Test func twiceAroundRepeatsEverythingAfterTheFirstMark() {
        let course = [entry(1, a), entry(2, b), entry(3, c)]
        let result = computeCourseLegs(course, opts: CourseLegOptions(defaultRounding: nil, twiceAround: true, startUid: nil, variationDeg: 0))

        // sailed = A, B, C, B, C -> 4 legs.
        #expect(result.legs.count == 4)
        #expect(result.legs.map(\.fromLabel) == ["A", "B", "C", "B"])
        #expect(result.legs.map(\.toLabel) == ["B", "C", "B", "C"])
        // mapPoints mirrors the sailed sequence, 5 long.
        #expect(result.mapPoints.count == 5)
    }

    @Test func twiceAroundIsANoOpUnderTwoMarks() {
        let course = [entry(1, a)]
        let result = computeCourseLegs(course, opts: CourseLegOptions(defaultRounding: nil, twiceAround: true, startUid: nil, variationDeg: 0))
        #expect(result.mapPoints.count == 1)
        #expect(result.legs.isEmpty)
    }

    @Test func mapPointsCarryEffectiveRoundingAndStartFlag() {
        let course = [
            entry(1, a, rounding: nil),
            entry(2, b, rounding: .port),
        ]
        let result = computeCourseLegs(course, opts: CourseLegOptions(defaultRounding: .starboard, twiceAround: false, startUid: 1, variationDeg: 0))
        #expect(result.mapPoints[0]?.isStart == true)
        #expect(result.mapPoints[0]?.rounding == .starboard) // inherits the default
        #expect(result.mapPoints[1]?.rounding == .port) // entry's own rounding wins
    }

    @Test func unplacedEntriesListsOnlyEntriesWithoutAResolvedPosition() {
        let course = [entry(1, a), entry(2, mark("X", portable: true)), entry(3, b)]
        let unplaced = unplacedEntries(course)
        #expect(unplaced.count == 1)
        #expect(unplaced[0].mark.code == "X")
    }
}
