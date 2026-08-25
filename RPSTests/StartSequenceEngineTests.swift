//
//  StartSequenceEngineTests.swift
//  RPSTests
//
//  Mirrors the reference app's start-sequence.service.spec.ts, adapted to
//  the pure, clock-driven engine: every case drives `now` explicitly rather
//  than waiting on a real interval, matching the reference's own approach of
//  advancing a faked clock instead of sleeping.
//

import Testing
import Foundation
@testable import RPS

private let baseNow = Date(timeIntervalSince1970: 1_787_760_000) // 2026-08-24T18:00:00Z-ish, exact value unimportant

struct StartSequenceEngineTests {

    @Test func idleWithNoStartHasNoSecondsAndDashDisplay() {
        #expect(StartSequenceEngine.phase(secondsToStart: nil) == .idle)
        #expect(StartSequenceEngine.display(secondsToStart: nil) == "—:—")
    }

    // Arming happens whenever the thumb lands, not on a second boundary, and
    // an armed five-minute sequence must read 5:00 however far into the
    // second it was armed.
    @Test func readsACleanWholeMinuteHoweverFarIntoASecondItWasArmed() {
        for offsetMs in [0, 1, 250, 499, 500, 501, 750, 999] {
            let armedAt = baseNow.addingTimeInterval(Double(offsetMs) / 1000)
            let startAt = armedAt.addingTimeInterval(5 * 60)
            let s = StartSequenceEngine.secondsToStart(startAt: startAt, now: armedAt)
            #expect(s == 300, "armed \(offsetMs)ms into the second")
            #expect(StartSequenceEngine.display(secondsToStart: s) == "5:00")
        }
    }

    @Test func holdsEachSecondForAFullSecondAndHitsZeroOnTheGun() {
        let startAt = baseNow.addingTimeInterval(5 * 60)
        func displayAt(_ elapsed: Double) -> String {
            StartSequenceEngine.display(secondsToStart: StartSequenceEngine.secondsToStart(startAt: startAt, now: baseNow.addingTimeInterval(elapsed)))
        }
        #expect(displayAt(0.4) == "5:00")
        #expect(displayAt(0.8) == "5:00")
        #expect(displayAt(1.2) == "4:59")
        #expect(displayAt(300) == "0:00")
    }

    @Test func countsDownFromTheFiveMinuteGun() {
        let startAt = baseNow.addingTimeInterval(5 * 60)
        #expect(StartSequenceEngine.secondsToStart(startAt: startAt, now: baseNow) == 300)
        let s = StartSequenceEngine.secondsToStart(startAt: startAt, now: baseNow.addingTimeInterval(23))
        #expect(s == 277)
        #expect(StartSequenceEngine.display(secondsToStart: s) == "4:37")
    }

    @Test func walksThePhasesAndFlagsOfAStandardSequence() {
        let startAt = baseNow.addingTimeInterval(5 * 60)
        func phaseAt(_ elapsed: Double) -> SequencePhase {
            StartSequenceEngine.phase(secondsToStart: StartSequenceEngine.secondsToStart(startAt: startAt, now: baseNow.addingTimeInterval(elapsed)))
        }
        #expect(phaseAt(0) == .warning)
        #expect(StartSequenceEngine.flag(phase: .warning) == "Class flag up")
        #expect(phaseAt(60) == .preparatory) // 4:00
        #expect(StartSequenceEngine.flag(phase: .preparatory) == "P flag up")
        #expect(phaseAt(240) == .oneMinute) // 1:00
        #expect(StartSequenceEngine.flag(phase: .oneMinute) == "P flag down")
        #expect(phaseAt(300) == .racing) // the gun
        #expect(StartSequenceEngine.flag(phase: .racing) == "Started")
    }

    @Test func countsUpAfterTheStart() {
        let startAt = baseNow.addingTimeInterval(60)
        let s = StartSequenceEngine.secondsToStart(startAt: startAt, now: baseNow.addingTimeInterval(67))
        #expect(s == -7)
        #expect(StartSequenceEngine.display(secondsToStart: s) == "+0:07")
    }

    // The point of the whole feature: correcting a hand-started clock
    // against a gun that has already fired.
    @Test func syncSnapsALateStartUpToTheWholeMinute() {
        // thumb was three seconds late off the five: reads 3:57 after 63s.
        let s = 300 - 63
        #expect(s == 237)
        let synced = StartSequenceEngine.syncedStartAt(secondsToStart: s, now: baseNow)
        #expect(synced == baseNow.addingTimeInterval(240))
    }

    @Test func syncSnapsAnEarlyStartBackDownToTheWholeMinute() {
        let s = 300 - 57 // started early: reads 4:03
        let synced = StartSequenceEngine.syncedStartAt(secondsToStart: s, now: baseNow)
        #expect(synced == baseNow.addingTimeInterval(240))
    }

    @Test func syncLeavesTheRunInAloneRatherThanSnappingToTheGun() {
        let s = 300 - 285 // 0:15 to go — nothing to round down to but zero,
        // and snapping the run-in to the gun would be actively wrong.
        #expect(StartSequenceEngine.syncedStartAt(secondsToStart: s, now: baseNow) == nil)
    }

    @Test func syncDoesNothingWithNoSequenceRunning() {
        #expect(StartSequenceEngine.syncedStartAt(secondsToStart: nil, now: baseNow) == nil)
    }

    @Test func hapticFiresOnceAtEachMarkAndNotOtherwise() {
        #expect(StartSequenceEngine.hapticMarkIfDue(secondsToStart: 300, lastHapticAt: nil) == 300)
        #expect(StartSequenceEngine.hapticMarkIfDue(secondsToStart: 299, lastHapticAt: 300) == nil)
        #expect(StartSequenceEngine.hapticMarkIfDue(secondsToStart: 60, lastHapticAt: 61) == 60)
        // Already buzzed at this exact mark — don't buzz again.
        #expect(StartSequenceEngine.hapticMarkIfDue(secondsToStart: 60, lastHapticAt: 60) == nil)
        #expect(StartSequenceEngine.hapticMarkIfDue(secondsToStart: 0, lastHapticAt: 1) == 0)
    }

    @Test func isExpiredAfterTheElapsedLimit() {
        #expect(!StartSequenceEngine.isExpired(secondsToStart: -(3 * 60 * 60 - 1)))
        #expect(StartSequenceEngine.isExpired(secondsToStart: -(3 * 60 * 60 + 1)))
    }

    @Test func shouldReviveOnlyWithinTheElapsedLimit() {
        let fresh = baseNow.addingTimeInterval(-2 * 60 * 60)
        #expect(StartSequenceEngine.shouldRevive(startAt: fresh, now: baseNow))
        let stale = baseNow.addingTimeInterval(-5 * 60 * 60)
        #expect(!StartSequenceEngine.shouldRevive(startAt: stale, now: baseNow))
    }
}
