//
//  SailPlanTests.swift
//  RPSTests
//
//  The sail call is derived, not measured, so the arithmetic behind it has
//  to be right: getting the sign of the wind angle backwards would put the
//  boat on the wrong tack on screen, which is worse than showing nothing.
//

import Testing
import Foundation
@testable import RPS

@Suite("SailPlan")
struct SailPlanTests {

    @Test("Sailing straight at the wind is a beat, dead ahead")
    func deadUpwindIsABeat() {
        // Heading 000, wind from 000: the breeze is right on the bow.
        let plan = SailPlan(legHeadingDeg: 0, windFromDeg: 0)
        #expect(abs(plan.twaDeg) < 0.001)
        #expect(plan.isBeat)
        #expect(!plan.spinnaker)
    }

    @Test("Dead downwind is a run and wants the kite")
    func deadDownwindWantsAKite() {
        // Heading 000 with the wind from 180 is running away from it.
        let plan = SailPlan(legHeadingDeg: 0, windFromDeg: 180)
        #expect(abs(abs(plan.twaDeg) - 180) < 0.001)
        #expect(!plan.isBeat)
        #expect(plan.spinnaker)
    }

    @Test("Wind over the port side is port tack")
    func windOverPortIsPortTack() {
        // Heading 000, wind from 270 (the west) puts it over the left side.
        let plan = SailPlan(legHeadingDeg: 0, windFromDeg: 270)
        #expect(plan.tack == .port)
        #expect(plan.twaDeg < 0)
    }

    @Test("Wind over the starboard side is starboard tack")
    func windOverStarboardIsStarboardTack() {
        let plan = SailPlan(legHeadingDeg: 0, windFromDeg: 90)
        #expect(plan.tack == .starboard)
        #expect(plan.twaDeg > 0)
    }

    @Test("A beam reach is neither a beat nor a kite leg")
    func beamReachIsNeither() {
        let plan = SailPlan(legHeadingDeg: 0, windFromDeg: 90)
        #expect(abs(abs(plan.twaDeg) - 90) < 0.001)
        #expect(!plan.isBeat)
        #expect(!plan.spinnaker)
    }

    @Test("The beat threshold is a boundary, not a range check")
    func beatThresholdBoundary() {
        let inside = SailPlan(legHeadingDeg: 0, windFromDeg: SailPlan.beatThresholdDeg - 1)
        let outside = SailPlan(legHeadingDeg: 0, windFromDeg: SailPlan.beatThresholdDeg + 1)
        #expect(inside.isBeat)
        #expect(!outside.isBeat)
    }

    @Test("Wrapping past north doesn't flip the tack")
    func wrapsAcrossNorth() {
        // Heading 010 with wind from 350: the breeze is 20 degrees off the
        // bow, over the port side. Naive subtraction gives +340 and would
        // call this starboard.
        let plan = SailPlan(legHeadingDeg: 10, windFromDeg: 350)
        #expect(abs(plan.twaDeg + 20) < 0.001)
        #expect(plan.tack == .port)
        #expect(plan.isBeat)
    }

    @Test("A leg heading of 270 with wind from 180 is a starboard reach")
    func southerlyOnAWesterlyLeg() {
        // Sailing west, wind from the south: it's on the left... no - facing
        // west, south is to port. Wind from 180 relative to heading 270 is
        // -90.
        let plan = SailPlan(legHeadingDeg: 270, windFromDeg: 180)
        #expect(abs(plan.twaDeg + 90) < 0.001)
        #expect(plan.tack == .port)
    }

    @Test("Every angle produces a non-empty sail call")
    func alwaysSaysSomething() {
        for heading in stride(from: 0.0, to: 360.0, by: 15) {
            let plan = SailPlan(legHeadingDeg: heading, windFromDeg: 225)
            #expect(!plan.sails.isEmpty)
            #expect(!plan.pointOfSail.isEmpty)
        }
    }
}
