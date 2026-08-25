//
//  StartLine.swift
//  RPS
//
//  Start-line bias and approach, ported from the reference web app's
//  `start-line.util.ts`. Read the doc comments closely: the favoured end is
//  resolved by comparing each end's distance to the first mark, NOT by the
//  raw sign of the off-square angle - a natural-seeming but wrong shortcut,
//  because the angle folds both ends onto the same number.
//

import Foundation

enum StartLine {

    typealias LatLon = GeoMath.LatLon

    enum FavouredEnd: String {
        case pin
        case committee
        case square
    }

    /// Which end of the line is worth starting at, and by how much.
    struct LineBias {
        /// Bearing of the line, pin -> committee boat, degrees true.
        var lineBearing: Double
        var lengthM: Double
        /// Where the wind is coming from, inferred from the first leg.
        var windDirTrue: Double
        /// How far off square to the wind the line lies, -90..90. Positive
        /// means the pin end is the one further upwind.
        var biasDeg: Double
        var favoured: FavouredEnd
        /// Metres of upwind distance the favoured end is worth over the other.
        var advantageM: Double
    }

    /// Where the boat is relative to the line, and whether it will be over it
    /// before the gun.
    struct LineApproach {
        /// Metres to the line, measured square to it. Positive on the
        /// pre-start side; negative means the boat is already over.
        var distanceM: Double
        /// Seconds to reach the line at present speed. Nil when stopped.
        var timeToLineSec: Double?
        var over: Bool
    }

    /// How far off square the line is, 0..90 degrees.
    ///
    /// A line is a line, not an arrow: a bearing and its reciprocal describe
    /// the same line, so 157 degrees off square is really 23. Folding says how
    /// skewed the line is - but deliberately NOT which end that favours,
    /// because the two ends fold onto each other. Which end is favoured is
    /// settled separately, by measuring.
    private static func angleOffSquare(lineBearing: Double, windDirTrue: Double) -> Double {
        let raw = GeoMath.signedAngleDiff(target: lineBearing, from: windDirTrue + 90)
        let folded = raw > 90 ? raw - 180 : (raw < -90 ? raw + 180 : raw)
        return abs(folded)
    }

    /// Below this the line is square in any sense a sailor can use: the ends
    /// are pinged by walking a phone around a bouncing foredeck, which is
    /// worth a degree or two on its own.
    private static let squareDeadbandDeg = 2.0

    /// Works out which end of the start line is favoured.
    ///
    /// The wind direction is taken as the bearing from the middle of the line
    /// to the first mark. That holds when the first leg is a beat, which it
    /// nearly always is; on a reaching start it will be wrong, which is why
    /// the UI labels this as derived from the first leg rather than
    /// presenting it as a wind reading.
    ///
    /// The favoured end is then simply whichever end is further upwind, and
    /// the advantage is how much further upwind it is - the classic
    /// length x sin(bias) that tells you whether the pin is worth fighting
    /// for or worth a boat length.
    static func computeLineBias(pin: LatLon, committee: LatLon, firstMark: LatLon) -> LineBias {
        let lineBearing = GeoMath.initialBearing(lat1: pin.lat, lon1: pin.lon, lat2: committee.lat, lon2: committee.lon)
        let lengthM = GeoMath.haversineNm(lat1: pin.lat, lon1: pin.lon, lat2: committee.lat, lon2: committee.lon) * 1852
        let mid = GeoMath.midpoint(lat1: pin.lat, lon1: pin.lon, lat2: committee.lat, lon2: committee.lon)
        let windDirTrue = GeoMath.initialBearing(lat1: mid.lat, lon1: mid.lon, lat2: firstMark.lat, lon2: firstMark.lon)

        // A line square to the wind runs across it, so its bearing is the
        // wind direction turned 90 degrees, and how far the line is off that
        // is how skewed it is.
        let magnitude = angleOffSquare(lineBearing: lineBearing, windDirTrue: windDirTrue)

        // Which end that favours is then measured rather than inferred from
        // the angle's sign. The sign can't answer it: the fold above maps the
        // line onto itself, so the two ends land on the same number and the
        // answer comes out backwards for half of all lines depending only on
        // which end happened to get pinged first. The favoured end is by
        // definition the one further upwind, which is the one closer to the
        // mark, so that is what gets compared.
        let pinDist = GeoMath.haversineNm(lat1: pin.lat, lon1: pin.lon, lat2: firstMark.lat, lon2: firstMark.lon)
        let cmteDist = GeoMath.haversineNm(lat1: committee.lat, lon1: committee.lon, lat2: firstMark.lat, lon2: firstMark.lon)
        let favoured: FavouredEnd = magnitude < squareDeadbandDeg ? .square : (pinDist < cmteDist ? .pin : .committee)

        return LineBias(
            lineBearing: lineBearing,
            lengthM: lengthM,
            windDirTrue: windDirTrue,
            // Signed for the UI's convenience: positive means the pin is the
            // end to be at. The magnitude is what's off square either way.
            biasDeg: favoured == .committee ? -magnitude : magnitude,
            favoured: favoured,
            advantageM: lengthM * sin(magnitude * .pi / 180)
        )
    }

    /// How far the boat is from the line, signed so that positive is the side
    /// you are supposed to be on before the gun.
    ///
    /// Which side that is can't be assumed - it depends entirely on which end
    /// got pinged first - so it's derived from the course itself: the first
    /// mark is on the far side of the line, so the pre-start side is the
    /// other one.
    static func computeLineApproach(
        pin: LatLon, committee: LatLon, firstMark: LatLon, boat: LatLon, speedKts: Double?
    ) -> LineApproach {
        let markSideRaw = GeoMath.crossTrackM(
            fromLat: pin.lat, fromLon: pin.lon, toLat: committee.lat, toLon: committee.lon,
            pointLat: firstMark.lat, pointLon: firstMark.lon
        )
        let markSide = markSideRaw > 0 ? 1.0 : (markSideRaw < 0 ? -1.0 : 0.0)
        let raw = GeoMath.crossTrackM(
            fromLat: pin.lat, fromLon: pin.lon, toLat: committee.lat, toLon: committee.lon,
            pointLat: boat.lat, pointLon: boat.lon
        )
        // markSide == 0 would mean the first mark sits exactly on the line,
        // which isn't a course; treat it as "course side is to the right"
        // rather than collapsing every distance to zero.
        let distanceM = raw * -(markSide == 0 ? 1.0 : markSide)
        let metresPerSec: Double? = (speedKts.map { $0 > 0.2 } ?? false) ? speedKts! * 0.514444 : nil
        return LineApproach(
            distanceM: distanceM,
            timeToLineSec: metresPerSec.map { distanceM / $0 },
            over: distanceM < 0
        )
    }
}
