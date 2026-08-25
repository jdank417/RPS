//
//  CourseLegs.swift
//  RPS
//
//  Computes legs (heading/distance per leg), total distance, and map points
//  for a course. Ported from the reference app's `course-legs.util.ts`,
//  including its edge cases (zero-length legs, missing positions, the
//  "twice around" repeat rule). Pure and independently unit-testable.
//

import Foundation

struct LegInfo: Equatable, Identifiable {
    var legIndex: Int
    var fromLabel: String
    var toLabel: String
    var toMark: Mark
    var rounding: Rounding?
    var missing: Bool
    var distNm: Double?
    var trueHdg: Double?
    var magHdg: Double?

    var id: Int { legIndex }
}

struct MapPoint: Equatable, Identifiable {
    var lat: Double
    var lon: Double
    var label: String
    var name: String
    var govtLight: String?
    var portable: Bool
    var rounding: Rounding?
    var isStart: Bool
    /// Position in the sailed sequence. This is the identity: a course can
    /// legitimately visit the same mark more than once - a windward mark
    /// rounded twice, a start that is also the finish, or every mark after
    /// the first when "twice around" is up - and deriving the id from the
    /// mark's code and position instead gave those occurrences *identical*
    /// ids, which makes SwiftUI's ForEach render them as duplicates.
    var seq: Int = 0

    var id: Int { seq }
}

struct CourseComputation: Equatable {
    var legs: [LegInfo] = []
    var totalNm: Double = 0
    /// Parallel to the (possibly twice-around-expanded) course; nil where a
    /// position hasn't been resolved yet.
    var mapPoints: [MapPoint?] = []
}

struct CourseLegOptions {
    var defaultRounding: Rounding?
    var twiceAround: Bool
    var startUid: Int?
    var variationDeg: Double
}

func effectiveRounding(_ entry: CourseEntry, defaultRounding: Rounding?) -> Rounding? {
    entry.rounding ?? defaultRounding
}

/// The start is whichever entry a start position was applied to. Before
/// that, fall back to a leading mark whose name itself says "start" (some
/// clubs' own lists carry a portable "Start/Finish" mark), so a course typed
/// straight in still shows where it begins.
func isStartEntry(_ entry: CourseEntry, index: Int, startUid: Int?) -> Bool {
    if let startUid { return entry.uid == startUid }
    return index == 0 && entry.mark.name.range(of: "start", options: .caseInsensitive) != nil
}

/// The sequence actually sailed. With code flag T ("twice around") up, the
/// course repeats after the first mark - the start is passed once and
/// everything after it is sailed twice.
func courseForLegs(_ course: [CourseEntry], twiceAround: Bool) -> [CourseEntry] {
    guard twiceAround, course.count >= 2 else { return course }
    return course + course[1...]
}

func unplacedEntries(_ course: [CourseEntry]) -> [CourseEntry] {
    course.filter { resolvedPosition($0) == nil }
}

func computeCourseLegs(_ course: [CourseEntry], opts: CourseLegOptions) -> CourseComputation {
    let sailed = courseForLegs(course, twiceAround: opts.twiceAround)
    var mapPoints: [MapPoint?] = []
    var legs: [LegInfo] = []
    var totalNm = 0.0

    for i in 0..<sailed.count {
        let entry = sailed[i]
        let pos = resolvedPosition(entry)
        mapPoints.append(
            pos.map { p in
                MapPoint(
                    lat: p.lat,
                    lon: p.lon,
                    label: entry.mark.code,
                    name: entry.mark.name,
                    govtLight: entry.mark.govtLight,
                    portable: entry.mark.portable,
                    rounding: effectiveRounding(entry, defaultRounding: opts.defaultRounding),
                    isStart: isStartEntry(entry, index: i, startUid: opts.startUid),
                    seq: i
                )
            }
        )
        if i == 0 { continue }

        let legIndex = i - 1
        let prev = resolvedPosition(sailed[i - 1])
        let fromLabel = sailed[i - 1].mark.code
        let toLabel = entry.mark.code
        let rounding = effectiveRounding(entry, defaultRounding: opts.defaultRounding)

        guard let prev, let pos else {
            legs.append(LegInfo(legIndex: legIndex, fromLabel: fromLabel, toLabel: toLabel, toMark: entry.mark, rounding: rounding, missing: true))
            continue
        }

        let dist = GeoMath.haversineNm(lat1: prev.lat, lon1: prev.lon, lat2: pos.lat, lon2: pos.lon)
        // Two marks resolving to the same spot give a zero-length leg whose
        // bearing is meaningless.
        if dist < 0.005 {
            legs.append(LegInfo(legIndex: legIndex, fromLabel: fromLabel, toLabel: toLabel, toMark: entry.mark, rounding: rounding, missing: true))
            continue
        }

        let trueHdg = GeoMath.initialBearing(lat1: prev.lat, lon1: prev.lon, lat2: pos.lat, lon2: pos.lon)
        let magHdg = GeoMath.applyVariation(trueHeadingDeg: trueHdg, variationDeg: opts.variationDeg)
        totalNm += dist
        legs.append(LegInfo(
            legIndex: legIndex, fromLabel: fromLabel, toLabel: toLabel, toMark: entry.mark,
            rounding: rounding, missing: false, distNm: dist, trueHdg: trueHdg, magHdg: magHdg
        ))
    }

    return CourseComputation(legs: legs, totalNm: totalNm, mapPoints: mapPoints)
}
