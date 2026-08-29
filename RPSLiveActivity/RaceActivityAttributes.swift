//
//  RaceActivityAttributes.swift
//  RPS / RPSLiveActivity
//
//  The Lock Screen / Dynamic Island contract for a race's Live Activity.
//  This file has to compile into BOTH targets - the main RPS app (which
//  starts and updates the Activity from live GPS/wind/course state) and
//  this widget extension (which only renders it) - because ActivityKit
//  identifies an Activity by this exact Swift type, not just a matching
//  shape. It lives here, in the widget extension's folder, with the main
//  RPS target added to it under Xcode's File Inspector -> Target
//  Membership. That one checkbox is a manual step - nothing else needed.
//

import ActivityKit
import Foundation

struct RaceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the start sequence is armed - nil once no sequence is
        /// running. The Lock Screen renders the countdown itself from this
        /// (`Text(startAt, style: .timer)`, which the system keeps ticking
        /// on its own, counting down before the gun and up afterward), so
        /// this only needs pushing when the sequence is armed, bumped, or
        /// synced - not every second.
        var startAt: Date?
        /// What the RC is flying right now - "Class flag up", "P flag up",
        /// "P flag down", "Started".
        var flag: String
        var isRacing: Bool
        /// "W1 -> L1", when a leg is being sailed.
        var legLabel: String?
        var distNm: Double?
        var bearingTrue: Double?
        var windFromDeg: Double?
        var windSpeedKts: Double?
    }

    /// Which club/list the course was built from - fixed for the life of
    /// one race, so it's an attribute rather than something re-sent with
    /// every content update.
    var clubName: String
}
