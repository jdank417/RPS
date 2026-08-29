//
//  RaceLiveActivityManager.swift
//  RPS
//
//  Starts, updates, and ends the race's Live Activity - the Lock Screen /
//  Dynamic Island card that shows the start countdown and, once racing,
//  the current leg, bearing, and wind, without unlocking the phone.
//  `RaceActivityAttributes` is defined in the RPSLiveActivity target and
//  shared into this one (see that file's header) so both processes agree
//  on the same Activity type.
//
//  Tied 1:1 to the start sequence's own lifecycle: armed = started,
//  stopped = ended. That's the closest thing this app has to an explicit
//  "I am racing now" moment, and it's already a well-tested, persisted
//  state machine - this doesn't duplicate that, just mirrors it outward.
//

import Foundation
import Observation
import ActivityKit

@Observable
@MainActor
final class RaceLiveActivityManager {

    private var activity: Activity<RaceActivityAttributes>?
    private var lastPushedState: RaceActivityAttributes.ContentState?
    private var lastPushedAt: Date?

    /// Below this, a changed distance/bearing/wind isn't worth a fresh push
    /// on its own - the countdown timer (rendered natively by the system
    /// from `startAt`) is what's actually live-updating for a sailor
    /// glancing at the lock screen; the numbers under it just need to be
    /// roughly current, not per-second.
    private static let minPushInterval: TimeInterval = 20

    var isActive: Bool { activity != nil }

    /// Call this whenever anything the activity shows might have changed -
    /// cheap even when nothing did, since it only pushes to the system
    /// when the content has genuinely changed (or the throttle has
    /// elapsed) rather than on every call.
    func sync(
        clubName: String,
        running: Bool,
        startAt: Date?,
        flag: String,
        isRacing: Bool,
        legLabel: String?,
        distNm: Double?,
        bearingTrue: Double?,
        windFromDeg: Double?,
        windSpeedKts: Double?
    ) {
        guard running else {
            end()
            return
        }

        let state = RaceActivityAttributes.ContentState(
            startAt: startAt,
            flag: flag,
            isRacing: isRacing,
            legLabel: legLabel,
            distNm: distNm,
            bearingTrue: bearingTrue,
            windFromDeg: windFromDeg,
            windSpeedKts: windSpeedKts
        )

        guard let activity else {
            start(clubName: clubName, state: state)
            return
        }

        guard shouldPush(state) else { return }
        push(activity, state)
    }

    func end() {
        guard let activity, let finalState = lastPushedState else { return }
        self.activity = nil
        lastPushedState = nil
        lastPushedAt = nil
        Task {
            // .default rather than .immediate: the Activity ending is the
            // race finishing, and a sailor who's just crossed the line
            // gets a moment to see the card confirm that before the system
            // clears it, rather than it vanishing mid-glance.
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .default
            )
        }
    }

    // MARK: - Internals

    private func shouldPush(_ state: RaceActivityAttributes.ContentState) -> Bool {
        guard let lastPushedState else { return true }
        if state.flag != lastPushedState.flag { return true }
        if state.isRacing != lastPushedState.isRacing { return true }
        if state.legLabel != lastPushedState.legLabel { return true }
        if state.startAt != lastPushedState.startAt { return true }
        if let lastPushedAt, Date().timeIntervalSince(lastPushedAt) < Self.minPushInterval {
            return false
        }
        return true
    }

    private func start(clubName: String, state: RaceActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let attributes = RaceActivityAttributes(clubName: clubName)
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            self.activity = activity
            lastPushedState = state
            lastPushedAt = Date()
        } catch {
            // A Live Activity is a bonus on the lock screen, not something
            // racing depends on - permission denied, the simulator, or the
            // per-app activity limit shouldn't interrupt anything else the
            // app is doing.
        }
    }

    private func push(_ activity: Activity<RaceActivityAttributes>, _ state: RaceActivityAttributes.ContentState) {
        lastPushedState = state
        lastPushedAt = Date()
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }
}
