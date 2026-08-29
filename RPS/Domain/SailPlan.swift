//
//  SailPlan.swift
//  RPS
//
//  What a leg's wind angle means for the boat: which tack, what point of
//  sail, and how the true wind angle relates to it.
//

import Foundation

/// A leg's relationship to the wind, derived from the leg's own heading.
///
/// The heading used is the leg's rhumb line, which is what the boat sails on
/// a reach or a run. On a beat it isn't - you cannot sail at the mark - and
/// that is precisely the thing worth knowing before the start, so `isBeat`
/// calls it out rather than quietly reporting an angle no one can hold.
struct SailPlan: Equatable {
    /// True wind angle for this leg, -180...180. Negative is wind over the
    /// port side.
    let twaDeg: Double
    let tack: SailingMath.Tack
    let pointOfSail: String
    /// The leg cannot be sailed directly - it's a beat, and the boat will
    /// work upwind in tacks.
    let isBeat: Bool
    /// Whether a downwind sail is worth setting for this leg.
    let spinnaker: Bool

    /// Below this the mark is inside the no-go zone: the leg is a beat and
    /// the rhumb line is not sailable. 40 degrees is a workable middle for
    /// the keelboats this is aimed at - a boat that points higher will beat
    /// slightly closer, which is why this is framed as "expect to tack"
    /// rather than a number to steer by.
    static let beatThresholdDeg: Double = 40

    /// Past this the apparent wind is far enough aft that a kite pays.
    static let spinnakerThresholdDeg: Double = 100

    init(legHeadingDeg: Double, windFromDeg: Double) {
        let twa = SailingMath.trueWindAngle(cogDeg: legHeadingDeg, windFromDeg: windFromDeg)
        let magnitude = abs(twa)

        twaDeg = twa
        tack = SailingMath.tack(fromWindAngle: twa)
        pointOfSail = SailingMath.pointOfSail(twaDeg: twa)
        isBeat = magnitude < Self.beatThresholdDeg
        spinnaker = magnitude >= Self.spinnakerThresholdDeg
    }
}
