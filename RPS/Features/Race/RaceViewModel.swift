//
//  RaceViewModel.swift
//  RPS
//
//  Ties the live GPS fix, the built course, and forecast wind together into
//  what Race Mode actually shows: bearing/range/VMG to the next mark, true
//  wind angle/tack/point-of-sail, and start-line bias/approach from two
//  pinged GPS fixes (pin end, committee-boat end).
//

import Foundation
import Observation
import CoreLocation

/// Bearing and range from the boat's present position to the mark it is
/// currently sailing to — what a sailor actually steers by, as opposed to
/// the mark-to-mark bearing the course was planned on. The moment you tack,
/// or get set by current, the rhumb line the course was built on is wrong;
/// this is continuously recomputed from wherever the boat actually is.
struct LiveVector: Equatable {
    var bearingTrue: Double
    var bearingMag: Double
    var distNm: Double
    /// Signed difference between where the boat is pointing and where the
    /// mark is, -180..180. Negative = the mark is to port. Nil unless moving.
    var offCourseDeg: Double?
    /// Minutes to the mark at present speed, when moving.
    var etaMin: Double?
}

@Observable
@MainActor
final class RaceViewModel {

    let courseStore: CourseStateStore
    let liveStore: LivePositionStore
    let windService: WindService

    /// The pinged GPS fix for the committee-boat end, stamped by "Ping
    /// Committee Boat". Always a live ping: a boat, unlike a charted mark,
    /// never has a position worth trusting from the chart, and it isn't a
    /// course entry the way the pin end is - there's no leg that starts or
    /// ends "at the committee boat" for it to live on.
    private(set) var committee: GeoMath.LatLon?

    /// Mirrors `CourseStateStore`'s own UserDefaults persistence for the
    /// committee-boat ping, so it survives the app being backgrounded or
    /// relaunched. The pin end has no counterpart here - its position lives
    /// on the start's own `CourseEntry` (see `pin` below), which is already
    /// durable via `CourseStateStore.persist()`.
    private struct PersistedLine: Codable {
        var committee: GeoMath.LatLon?
    }

    private static let lineCacheKey = "rps.cache.startLine"

    init(courseStore: CourseStateStore, liveStore: LivePositionStore, windService: WindService) {
        self.courseStore = courseStore
        self.liveStore = liveStore
        self.windService = windService
        restoreLine()
    }

    // MARK: - Start line

    /// The pin end of the start line - always the start's own `CourseEntry`
    /// position, whatever it came from: a charted mark, a manual entry in
    /// the course builder, or a live GPS ping. This used to keep a second,
    /// view-model-only copy for a pinged start, which is why pinging it here
    /// didn't show up in the leg navigator, the map's actual course line, or
    /// the VMG-to-mark math - none of those read this view model, they all
    /// read the course, so pinging anywhere now updates the one place
    /// everything else already looks.
    var pin: GeoMath.LatLon? {
        guard let entry = courseStore.startEntry, let position = resolvedPosition(entry) else { return nil }
        return GeoMath.LatLon(lat: position.lat, lon: position.lon)
    }

    func pingPin() {
        guard let fix = liveStore.fix, let entry = courseStore.startEntry else { return }
        courseStore.pingMark(code: entry.mark.code, lat: fix.lat, lon: fix.lon)
    }

    func pingCommittee() {
        guard let fix = liveStore.fix else { return }
        committee = GeoMath.LatLon(lat: fix.lat, lon: fix.lon)
        persistLine()
    }

    func clearLine() {
        // A charted mark's position isn't something "Clear Line" should be
        // able to erase - it stays put regardless, same reasoning as why
        // the pin ping button is hidden for one in the first place.
        if !courseStore.startIsChartedMark, let entry = courseStore.startEntry {
            courseStore.clearPosition(code: entry.mark.code)
        }
        committee = nil
        persistLine()
    }

    private func persistLine() {
        let snapshot = PersistedLine(committee: committee)
        guard snapshot.committee != nil else {
            UserDefaults.standard.removeObject(forKey: Self.lineCacheKey)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.lineCacheKey)
            // See CourseStateStore.persist(): forces the write to actually
            // reach disk before a force-quit right after pinging can kill
            // the process mid-flush.
            UserDefaults.standard.synchronize()
        }
    }

    private func restoreLine() {
        guard let data = UserDefaults.standard.data(forKey: Self.lineCacheKey),
              let saved = try? JSONDecoder().decode(PersistedLine.self, from: data) else { return }
        committee = saved.committee
    }

    /// The mark the first leg is sailed to — used both as the "which way is
    /// upwind" reference for line bias and as the map's start-line context.
    var firstMarkPosition: GeoMath.LatLon? {
        let points = courseStore.legComputation.mapPoints
        guard points.count > 1 else { return nil }
        guard let point = points.dropFirst().compactMap({ $0 }).first else { return nil }
        return GeoMath.LatLon(lat: point.lat, lon: point.lon)
    }

    var lineBias: StartLine.LineBias? {
        guard let pin, let committee, let firstMark = firstMarkPosition else { return nil }
        return StartLine.computeLineBias(pin: pin, committee: committee, firstMark: firstMark)
    }

    var lineApproach: StartLine.LineApproach? {
        guard let pin, let committee, let firstMark = firstMarkPosition, let fix = liveStore.fix else { return nil }
        let boat = GeoMath.LatLon(lat: fix.lat, lon: fix.lon)
        return StartLine.computeLineApproach(pin: pin, committee: committee, firstMark: firstMark, boat: boat, speedKts: fix.speedKts)
    }

    // MARK: - Live vector to next mark

    var vector: LiveVector? {
        guard let fix = liveStore.fix, let idx = courseStore.currentLegIndex else { return nil }
        let points = courseStore.legComputation.mapPoints
        // mapPoints[i] is the mark at the *end* of leg i-1, so leg `idx`
        // targets mapPoints[idx + 1].
        guard idx + 1 < points.count, let target = points[idx + 1] else { return nil }

        let bearingTrue = GeoMath.initialBearing(lat1: fix.lat, lon1: fix.lon, lat2: target.lat, lon2: target.lon)
        let distNm = GeoMath.haversineNm(lat1: fix.lat, lon1: fix.lon, lat2: target.lat, lon2: target.lon)
        let heading = fix.headingDeg
        let speed = fix.speedKts

        return LiveVector(
            bearingTrue: bearingTrue,
            bearingMag: GeoMath.applyVariation(trueHeadingDeg: bearingTrue, variationDeg: courseStore.variationDeg),
            distNm: distNm,
            offCourseDeg: (heading != nil && liveStore.moving) ? GeoMath.signedAngleDiff(target: bearingTrue, from: heading!) : nil,
            etaMin: (speed != nil && speed! >= 0.5) ? (distNm / speed!) * 60 : nil
        )
    }

    var vmgToMark: Double? {
        guard let fix = liveStore.fix, let vector, let cog = fix.headingDeg, let sog = fix.speedKts else { return nil }
        return SailingMath.vmgToMark(sogKts: sog, cogDeg: cog, bearingToMarkDeg: vector.bearingTrue)
    }

    // MARK: - Wind

    var trueWindAngle: Double? {
        guard let cog = liveStore.fix?.headingDeg, let wind = windService.wind else { return nil }
        return SailingMath.trueWindAngle(cogDeg: cog, windFromDeg: wind.fromDeg)
    }

    var tack: SailingMath.Tack? {
        trueWindAngle.map(SailingMath.tack(fromWindAngle:))
    }

    var pointOfSail: String? {
        trueWindAngle.map(SailingMath.pointOfSail(twaDeg:))
    }

    var windCompassPoint: String? {
        windService.wind.map { SailingMath.compassPoint($0.fromDeg) }
    }

    func refreshWindIfNeeded() {
        guard let fix = liveStore.fix else { return }
        Task { await windService.refresh(lat: fix.lat, lon: fix.lon) }
    }
}
