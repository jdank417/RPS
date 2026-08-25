//
//  StartSequenceEngine.swift
//  RPS
//
//  Pure logic for the race start sequence, ported from the reference app's
//  `start-sequence.service.ts` — the DESIGN, not the Angular/RxJS mechanics.
//  Time is read from an absolute epoch instant rather than decremented, so
//  backgrounding the app can't cause drift: everything here is a pure
//  function of "now" and the armed start instant, which is what makes it
//  independently testable without a running clock.
//

import Foundation

/// Where the sequence is, in the terms the RC uses on the water.
enum SequencePhase: Equatable {
    case idle
    /// Class flag up, 5:00 to 4:00.
    case warning
    /// P flag up, 4:00 to 1:00.
    case preparatory
    /// P down, 1:00 to 0:00.
    case oneMinute
    /// The gun has gone.
    case racing
}

enum StartSequenceEngine {

    /// How long after the gun the timer keeps counting up before it gives up
    /// and resets - long enough for a windward-leeward, short enough that
    /// yesterday's sequence isn't still running when you open the app
    /// tonight.
    static let elapsedLimitSec: Double = 3 * 60 * 60

    /// Seconds-to-go at which the phone buzzes. The minute guns, then the
    /// run-in to the start, then every one of the last five seconds.
    static let hapticMarks: Set<Int> = [300, 240, 180, 120, 60, 30, 20, 10, 5, 4, 3, 2, 1, 0]

    /// Whole seconds left until `startAt`, ceiling-rounded so an armed
    /// five-minute sequence reads 5:00 for the whole of its first second and
    /// reaches 0:00 exactly on the gun rather than a second early.
    static func secondsToStart(startAt: Date, now: Date) -> Int {
        Int((startAt.timeIntervalSince(now)).rounded(.up))
    }

    static func phase(secondsToStart s: Int?) -> SequencePhase {
        guard let s else { return .idle }
        if s <= 0 { return .racing }
        if s <= 60 { return .oneMinute }
        if s <= 240 { return .preparatory }
        return .warning
    }

    /// What should be flying, so the sailor can check the timer against the
    /// committee boat rather than trusting it blind.
    static func flag(phase: SequencePhase) -> String {
        switch phase {
        case .warning: return "Class flag up"
        case .preparatory: return "P flag up"
        case .oneMinute: return "P flag down"
        case .racing: return "Started"
        case .idle: return ""
        }
    }

    /// "4:32", or "+1:07" once racing.
    static func display(secondsToStart s: Int?) -> String {
        guard let s else { return "—:—" }
        let sign = s < 0 ? "+" : ""
        let abs = abs(s)
        let mins = abs / 60
        let secs = abs % 60
        return "\(sign)\(mins):\(String(format: "%02d", secs))"
    }

    /// Snaps the countdown to the nearest whole minute: the correction to
    /// apply on a gun. Rounding to the nearest rather than down means it
    /// corrects a timer started late (4:57 -> 5:00) and one started early
    /// (5:03 -> 5:00) alike, which matters because you can't tell in advance
    /// which way your thumb will be off. Returns nil when there's no minute
    /// left to round to (snapping the last of the run-in to the gun would be
    /// actively wrong) or no sequence is running.
    static func syncedStartAt(secondsToStart s: Int?, now: Date) -> Date? {
        guard let s else { return nil }
        let rounded = (Double(s) / 60).rounded() * 60
        guard rounded > 0 else { return nil }
        return now.addingTimeInterval(rounded)
    }

    /// Whether a haptic buzz should fire for a fresh reading of
    /// `secondsToStart`, given the last mark that already buzzed. Returns the
    /// new "last buzzed" mark to store when a buzz is due, else nil.
    static func hapticMarkIfDue(secondsToStart s: Int, lastHapticAt: Int?) -> Int? {
        guard s != lastHapticAt, hapticMarks.contains(s) else { return nil }
        return s
    }

    /// True once the sequence has been counting up so long it should be
    /// abandoned rather than shown (a stale sequence from a previous day).
    static func isExpired(secondsToStart s: Int) -> Bool {
        Double(-s) > elapsedLimitSec
    }

    /// Whether a persisted `startAt` (epoch) found on launch is still fresh
    /// enough to revive, vs. belonging to yesterday's sequence.
    static func shouldRevive(startAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(startAt) < elapsedLimitSec
    }
}
