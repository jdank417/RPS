//
//  SailingMathTests.swift
//  RPSTests
//
//  Mirrors the reference app's sailing.util.spec.ts.
//

import Testing
import Foundation
@testable import RPS

struct VMGTests {
    @Test func fullSpeedStraightAtTheMark() {
        #expect(abs(SailingMath.vmgToMark(sogKts: 6, cogDeg: 90, bearingToMarkDeg: 90) - 6) < 1e-6)
    }

    @Test func zeroWhenMarkIsAbeam() {
        #expect(abs(SailingMath.vmgToMark(sogKts: 6, cogDeg: 0, bearingToMarkDeg: 90)) < 1e-6)
        #expect(abs(SailingMath.vmgToMark(sogKts: 6, cogDeg: 0, bearingToMarkDeg: 270)) < 1e-6)
    }

    @Test func negativeWhenSailingAway() {
        #expect(abs(SailingMath.vmgToMark(sogKts: 6, cogDeg: 0, bearingToMarkDeg: 180) - (-6)) < 1e-6)
    }

    @Test func discountsSpeedByAngleOffTheMark() {
        let expected = 6 * cos(Double.pi / 4)
        #expect(abs(SailingMath.vmgToMark(sogKts: 6, cogDeg: 45, bearingToMarkDeg: 0) - expected) < 1e-6)
        #expect(abs(SailingMath.vmgToMark(sogKts: 6, cogDeg: 315, bearingToMarkDeg: 0) - expected) < 1e-6)
    }

    @Test func zeroWhenStopped() {
        #expect(SailingMath.vmgToMark(sogKts: 0, cogDeg: 123, bearingToMarkDeg: 45) == 0)
    }
}

struct TrueWindAngleTests {
    @Test func zeroHeadToWind() {
        #expect(SailingMath.trueWindAngle(cogDeg: 0, windFromDeg: 0) == 0)
        #expect(SailingMath.trueWindAngle(cogDeg: 230, windFromDeg: 230) == 0)
    }

    @Test func oneEightyDeadDownwind() {
        #expect(abs(SailingMath.trueWindAngle(cogDeg: 180, windFromDeg: 0)) == 180)
    }

    @Test func signsByWhichSideTheWindIsOn() {
        #expect(SailingMath.trueWindAngle(cogDeg: 90, windFromDeg: 0) == -90)
        #expect(SailingMath.trueWindAngle(cogDeg: 270, windFromDeg: 0) == 90)
    }

    @Test func staysWithinRangeAcrossTheCompass() {
        var cog = 0.0
        while cog < 360 {
            var wind = 0.0
            while wind < 360 {
                let twa = SailingMath.trueWindAngle(cogDeg: cog, windFromDeg: wind)
                #expect(twa > -181)
                #expect(twa <= 180)
                wind += 11
            }
            cog += 7
        }
    }
}

struct TackTests {
    @Test func windOverPortSideIsPortTack() {
        #expect(SailingMath.tack(fromWindAngle: -45) == .port)
        #expect(SailingMath.tack(fromWindAngle: -150) == .port)
    }

    @Test func windOverStarboardSideIsStarboardTack() {
        #expect(SailingMath.tack(fromWindAngle: 45) == .starboard)
        #expect(SailingMath.tack(fromWindAngle: 150) == .starboard)
    }

    @Test func agreesWithTrueWindAngleHeadingEastInANortherly() {
        let twa = SailingMath.trueWindAngle(cogDeg: 90, windFromDeg: 0)
        #expect(SailingMath.tack(fromWindAngle: twa) == .port)
    }
}

struct PointOfSailTests {
    @Test(arguments: [
        (twa: 0.0, label: "No-go zone"),
        (twa: 20.0, label: "No-go zone"),
        (twa: 45.0, label: "Close hauled"),
        (twa: -45.0, label: "Close hauled"),
        (twa: 70.0, label: "Close reach"),
        (twa: 90.0, label: "Beam reach"),
        (twa: -90.0, label: "Beam reach"),
        (twa: 120.0, label: "Broad reach"),
        (twa: 175.0, label: "Running"),
        (twa: -180.0, label: "Running"),
    ] as [(twa: Double, label: String)])
    func namesTheRightLabel(_ pair: (twa: Double, label: String)) {
        #expect(SailingMath.pointOfSail(twaDeg: pair.twa) == pair.label)
    }
}

struct CompassPointTests {
    @Test func namesTheCardinals() {
        #expect(SailingMath.compassPoint(0) == "N")
        #expect(SailingMath.compassPoint(90) == "E")
        #expect(SailingMath.compassPoint(180) == "S")
        #expect(SailingMath.compassPoint(270) == "W")
    }

    @Test func wrapsPast360AndBelowZero() {
        #expect(SailingMath.compassPoint(360) == "N")
        #expect(SailingMath.compassPoint(359) == "N")
        #expect(SailingMath.compassPoint(-90) == "W")
    }

    @Test func namesTheIntercardinals() {
        #expect(SailingMath.compassPoint(45) == "NE")
        #expect(SailingMath.compassPoint(225) == "SW")
        #expect(SailingMath.compassPoint(230) == "SW")
    }
}
