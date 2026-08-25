//
//  SailingMath.swift
//  RPS
//
//  Pure sailing math, ported from the reference web app's `sailing.util.ts`:
//  VMG to a mark, true wind angle, tack, point-of-sail label, and 16-point
//  compass label.
//

import Foundation

enum SailingMath {

    /// Speed made good towards the mark, in knots.
    ///
    /// Boat speed on its own flatters you: you can be doing seven knots on a
    /// heading that is barely closing the mark, and beating into wind you are
    /// never pointing at it at all. VMG is the number that says whether the
    /// last five minutes actually gained anything, which is why it's what you
    /// tune a beat against rather than speed.
    ///
    /// Negative when the boat is going away from the mark - which is real and
    /// worth showing, not an error.
    static func vmgToMark(sogKts: Double, cogDeg: Double, bearingToMarkDeg: Double) -> Double {
        let off = GeoMath.signedAngleDiff(target: bearingToMarkDeg, from: cogDeg)
        return sogKts * cos(off * .pi / 180)
    }

    /// True wind angle: where the wind is relative to the bow, -180..180.
    ///
    /// 0 is head to wind, ±180 is dead downwind. The sign follows the side the
    /// wind is on, so it doubles as which tack you're on: negative means the
    /// wind is over the port side, which is port tack, and that is the one
    /// that has to give way.
    ///
    /// `windFromDeg` is meteorological convention - the direction the wind is
    /// coming *from*, which is how every forecast and every masthead readout
    /// quotes it.
    static func trueWindAngle(cogDeg: Double, windFromDeg: Double) -> Double {
        GeoMath.signedAngleDiff(target: windFromDeg, from: cogDeg)
    }

    enum Tack: String {
        case port
        case starboard
    }

    /// Which tack a given wind angle puts you on. Dead head-to-wind has no
    /// answer, so it resolves to starboard rather than throwing - at 0 degrees
    /// you are not sailing either way.
    static func tack(fromWindAngle twaDeg: Double) -> Tack {
        twaDeg < 0 ? .port : .starboard
    }

    /// The point of sail, named the way it would be called on board.
    ///
    /// The boundaries are approximate by nature - a boat that points high and
    /// one that doesn't disagree about where close-hauled ends - so this is a
    /// label to orient by, not a trim instruction.
    static func pointOfSail(twaDeg: Double) -> String {
        let a = abs(twaDeg)
        if a < 35 { return "No-go zone" }
        if a < 55 { return "Close hauled" }
        if a < 80 { return "Close reach" }
        if a < 100 { return "Beam reach" }
        if a < 150 { return "Broad reach" }
        return "Running"
    }

    /// Compass point for a bearing - "SW" reads faster than "230°" when what
    /// you want is only roughly where the breeze is.
    private static let compass = [
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
    ]

    static func compassPoint(_ deg: Double) -> String {
        let normalized = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let idx = Int((normalized / 22.5).rounded()) % 16
        return compass[idx]
    }
}
