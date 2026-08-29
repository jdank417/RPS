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
import WidgetKit

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

    /// Tracked separately from the Live Activity's own push state: whether
    /// a Live Activity could be started at all (permission denied, the
    /// simulator, whatever) has nothing to do with whether RPSRaceWidget
    /// should still be able to mirror the race, so this can't just piggy-
    /// back on `lastPushedState`/`lastPushedAt` above.
    private var lastWidgetState: RaceActivityAttributes.ContentState?
    private var lastWidgetPushAt: Date?

    var isActive: Bool { activity != nil }

    /// Picks up an activity that outlived a previous app session - Live
    /// Activities keep running (and keep sitting on the Lock Screen) even
    /// after the app that started them is force-quit, but this manager's
    /// `activity` reference is plain in-memory state that doesn't survive
    /// that. Without this, a killed-and-relaunched app has no way to
    /// update *or end* one it no longer remembers starting - which is
    /// exactly how one gets stuck on the Lock Screen looking abandoned.
    /// Call once, e.g. when the app appears.
    func reconnect(isSequenceRunning: Bool) {
        guard activity == nil else { return }
        let existing = Array(Activity<RaceActivityAttributes>.activities)
        guard let found = existing.first else { return }

        if isSequenceRunning {
            // Still genuinely racing - adopt it so future syncs update the
            // same card instead of leaving it stale and starting a second
            // one alongside it.
            activity = found
            lastPushedState = found.content.state
            lastPushedAt = nil
            // Also gets RPSRaceWidget showing the right thing immediately
            // at launch, rather than only after the Race tab is opened.
            syncWidget(found.content.state)
        } else {
            // Nothing should still be running - this is exactly the
            // "stuck" case, so clear it out immediately rather than
            // waiting for the system's own multi-hour timeout.
            print("RaceLiveActivityManager: ending orphaned activity \(found.id) from a previous session")
            Task { await found.end(nil, dismissalPolicy: .immediate) }
            syncWidget(nil)
        }

        // Belt and suspenders - there should only ever be one, but if a
        // previous bug (or a crash mid-update) left more than one behind,
        // clear the rest out too.
        for extra in existing.dropFirst() {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

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
            syncWidget(nil)
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

        // Independent of whether the Live Activity itself starts/updates
        // below - RPSRaceWidget doesn't need Live Activities to be enabled
        // to do its own job.
        syncWidget(state)

        guard let activity else {
            start(clubName: clubName, state: state)
            return
        }

        guard shouldPush(state) else { return }
        push(activity, state)
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        lastPushedState = nil
        lastPushedAt = nil
        Task {
            // .immediate: this fires when the sailor taps "Cancel
            // Sequence" (or, from reconnect(), on an orphaned activity
            // from a previous session) - an explicit "get this off my
            // Lock Screen now", not a race finishing on its own. .default
            // would leave it lingering for up to four hours, which is
            // exactly the "stuck" complaint this is meant to fix.
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Widget

    /// Same throttle idea as `shouldPush`, kept as its own state so a
    /// disabled/denied Live Activity never blocks RPSRaceWidget from
    /// updating.
    private func syncWidget(_ state: RaceActivityAttributes.ContentState?) {
        guard shouldPushWidget(state) else { return }
        lastWidgetState = state
        lastWidgetPushAt = Date()
        WidgetSharedStore.saveRace(state)
        WidgetCenter.shared.reloadTimelines(ofKind: "RPSRaceWidget")
    }

    private func shouldPushWidget(_ state: RaceActivityAttributes.ContentState?) -> Bool {
        switch (lastWidgetState, state) {
        case (nil, nil):
            return false
        case (nil, .some), (.some, nil):
            return true
        case let (.some(last), .some(new)):
            if new.flag != last.flag { return true }
            if new.isRacing != last.isRacing { return true }
            if new.legLabel != last.legLabel { return true }
            if new.startAt != last.startAt { return true }
            if let lastWidgetPushAt, Date().timeIntervalSince(lastWidgetPushAt) < Self.minPushInterval {
                return false
            }
            return true
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
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("RaceLiveActivityManager: not starting - Live Activities are disabled (Settings > RPS > Live Activities, or Settings > Face ID & Passcode > Live Activities).")
            return
        }
        do {
            let attributes = RaceActivityAttributes(clubName: clubName)
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            self.activity = activity
            lastPushedState = state
            lastPushedAt = Date()
            print("RaceLiveActivityManager: started activity \(activity.id)")
        } catch {
            // A Live Activity is a bonus on the lock screen, not something
            // racing depends on - permission denied, the simulator, or the
            // per-app activity limit shouldn't interrupt anything else the
            // app is doing. Logged (not surfaced to the sailor) so a
            // failure here is at least visible in the Xcode console.
            print("RaceLiveActivityManager: failed to start activity - \(error)")
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
