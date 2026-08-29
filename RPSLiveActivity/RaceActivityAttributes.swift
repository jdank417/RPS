//
//  RaceActivityAttributes.swift
//  RPS / RPSLiveActivity
//
//  Everything the main RPS app and this widget extension need to agree on
//  the exact same definition of, in one place:
//   - the Lock Screen / Dynamic Island contract for a race's Live Activity
//     (ActivityKit identifies an Activity by this exact Swift type, not
//     just a matching shape)
//   - the shared-storage contract for the RPSWindWidget and RPSRaceWidget
//     Home Screen widgets
//  This file has to compile into BOTH targets, which is why it lives here
//  with the main RPS target added under Xcode's File Inspector -> Target
//  Membership. That one checkbox is a manual step - nothing else needed
//  for this file specifically (the widget's App Group is a separate step,
//  documented below on WidgetSharedStore).
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

// MARK: - Home Screen widget data

/// The latest wind reading, as the RPSWindWidget Home Screen widget needs
/// it. A plain WidgetKit widget (unlike a Live Activity) runs its
/// TimelineProvider in the widget extension's own process on the system's
/// own schedule - it can't be pushed to the way ActivityKit content is, so
/// it has to read whatever the main app last wrote somewhere both
/// processes can reach. That's an App Group container, not the app's own
/// UserDefaults.standard (which the extension process can't see at all).
struct WindWidgetSnapshot: Codable {
    var fromDeg: Double
    var speedKts: Double
    var gustKts: Double?
    var at: Date
}

enum WidgetSharedStore {
    /// Must match the App Group both the RPS and RPSLiveActivity targets
    /// are enrolled in (Signing & Capabilities -> + Capability -> App
    /// Groups) - that enrollment is a manual Xcode step, same idea as the
    /// Target Membership checkbox this file already needed.
    static let appGroupID = "group.JasonDank.RPS"
    private static let windKey = "rps.widget.wind"

    static func saveWind(_ snapshot: WindWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: windKey)
    }

    static func loadWind() -> WindWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: windKey) else { return nil }
        return try? JSONDecoder().decode(WindWidgetSnapshot.self, from: data)
    }

    private static let raceKey = "rps.widget.race"

    /// RPSRaceWidget's other half: whatever the Live Activity's content
    /// state currently is, or nil once the sequence stops - which is also
    /// what tells the widget to switch back to its "Start Race" layout.
    static func saveRace(_ state: RaceActivityAttributes.ContentState?) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        guard let state else {
            defaults.removeObject(forKey: raceKey)
            return
        }
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: raceKey)
    }

    static func loadRace() -> RaceActivityAttributes.ContentState? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: raceKey) else { return nil }
        return try? JSONDecoder().decode(RaceActivityAttributes.ContentState.self, from: data)
    }
}
