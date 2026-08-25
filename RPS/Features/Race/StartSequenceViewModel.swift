//
//  StartSequenceViewModel.swift
//  RPS
//
//  Stateful wrapper around `StartSequenceEngine`: a 250ms poll loop (reading
//  the clock, never decrementing a counter, so backgrounding the app can't
//  cause drift), haptic buzzes at the marks the reference app defines, and
//  persistence across app restarts via UserDefaults keyed by the start
//  epoch — ported from `start-sequence.service.ts`'s design.
//

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class StartSequenceViewModel {

    private static let defaultsKey = "rps.cache.start-sequence.startAt"

    private(set) var startAt: Date?
    private(set) var secondsToStart: Int?

    private var lastHapticAt: Int?
    private var pollTask: Task<Void, Never>?
    private let defaults: UserDefaults

    var running: Bool { startAt != nil }
    var phase: SequencePhase { StartSequenceEngine.phase(secondsToStart: secondsToStart) }
    var flag: String { StartSequenceEngine.flag(phase: phase) }
    var display: String { StartSequenceEngine.display(secondsToStart: secondsToStart) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    /// Arms a sequence `minutes` from now — the button pressed on the gun.
    func startIn(minutes: Double) {
        setStartAt(Date().addingTimeInterval(minutes * 60))
    }

    /// Snaps the countdown to the nearest whole minute: tap this on a gun.
    func sync() {
        guard let target = StartSequenceEngine.syncedStartAt(secondsToStart: secondsToStart, now: Date()) else { return }
        setStartAt(target)
    }

    /// Nudges the start later or earlier, for a postponement or a jumped gun.
    func bump(seconds: Double) {
        guard let startAt else { return }
        setStartAt(startAt.addingTimeInterval(seconds))
    }

    func stop() {
        startAt = nil
        secondsToStart = nil
        lastHapticAt = nil
        defaults.removeObject(forKey: Self.defaultsKey)
        stopTimer()
    }

    // MARK: - Internals

    private func setStartAt(_ at: Date) {
        startAt = at
        defaults.set(at.timeIntervalSince1970, forKey: Self.defaultsKey)
        // A buzz means a gun has just gone. Arming the timer on a whole
        // minute would otherwise fire one immediately, and a buzz that
        // doesn't mark anything is worse than no buzz — it's what teaches
        // you to ignore them.
        lastHapticAt = Int((at.timeIntervalSinceNow).rounded(.up))
        tick()
        startTimer()
    }

    private func restore() {
        let stored = defaults.double(forKey: Self.defaultsKey)
        guard stored > 0 else { return }
        let savedStartAt = Date(timeIntervalSince1970: stored)
        guard StartSequenceEngine.shouldRevive(startAt: savedStartAt, now: Date()) else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        startAt = savedStartAt
        // Reviving after a relaunch is not a gun either.
        lastHapticAt = Int((savedStartAt.timeIntervalSinceNow).rounded(.up))
        tick()
        startTimer()
    }

    private func startTimer() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            // The 250ms poll is what keeps the digit flipping within a
            // quarter second of the true time — a 1s one would drift
            // visibly against the committee boat's gun.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func stopTimer() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func tick() {
        guard let startAt else {
            secondsToStart = nil
            return
        }
        let s = StartSequenceEngine.secondsToStart(startAt: startAt, now: Date())
        if s == secondsToStart { return }
        secondsToStart = s
        if let mark = StartSequenceEngine.hapticMarkIfDue(secondsToStart: s, lastHapticAt: lastHapticAt) {
            lastHapticAt = mark
            buzz(forMark: mark)
        }
        if StartSequenceEngine.isExpired(secondsToStart: s) { stop() }
    }

    /// A buzz for each gun, because at one minute you are looking at the
    /// line and the fleet, not at a phone.
    private func buzz(forMark mark: Int) {
        if mark == 0 {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else if mark <= 5 {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.impactOccurred()
        } else {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
}
