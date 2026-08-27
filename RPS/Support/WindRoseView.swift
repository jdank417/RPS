//
//  WindRoseView.swift
//  RPS
//
//  A bird's-eye boat with the wind on it, for one leg.
//
//  Course-up rather than north-up: the boat points at the top of the dial
//  because that is the leg you are about to sail, and the wind swings round
//  it. That orientation is what makes the picture answerable at a glance -
//  "the breeze is over my left shoulder, kite's no use yet" - which a pair
//  of numbers on a card is not.
//

import SwiftUI

struct WindRoseView: View {
    /// The leg's heading, degrees true.
    let legHeadingDeg: Double
    /// Direction the wind is blowing *from*, degrees true.
    let windFromDeg: Double
    var size: CGFloat = 160

    private var plan: SailPlan {
        SailPlan(legHeadingDeg: legHeadingDeg, windFromDeg: windFromDeg)
    }

    var body: some View {
        ZStack {
            dial
            noGoWedge
            windArrow
            boat
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wind angle \(Int(abs(plan.twaDeg).rounded())) degrees, \(plan.tack == .port ? "port" : "starboard") tack, \(plan.pointOfSail)")
    }

    // MARK: - Pieces

    private var dial: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
            Circle()
                .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
            // Beam markers: the 90-degree points, which is where the call
            // between headsail and kite starts to change.
            ForEach([90.0, 180.0, 270.0], id: \.self) { angle in
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 1, height: 6)
                    .offset(y: -size / 2 + 3)
                    .rotationEffect(.degrees(angle))
            }
        }
    }

    /// The wedge either side of the bow the boat cannot sail in. Drawn so a
    /// beat is visible as "the mark is inside the shaded part" rather than
    /// having to be inferred from a number.
    private var noGoWedge: some View {
        Path { path in
            let c = CGPoint(x: size / 2, y: size / 2)
            path.move(to: c)
            path.addArc(
                center: c,
                radius: size / 2,
                startAngle: .degrees(-90 - SailPlan.beatThresholdDeg),
                endAngle: .degrees(-90 + SailPlan.beatThresholdDeg),
                clockwise: false
            )
            path.closeSubpath()
        }
        .fill(Color.red.opacity(0.10))
        // The wedge sits around the *wind*, not the bow: rotate it from
        // straight-up (where the boat points) to where the breeze is.
        .rotationEffect(.degrees(plan.twaDeg))
    }

    private var windArrow: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.accentColor)
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2.5, height: size * 0.30)
        }
        .offset(y: -size * 0.29)
        // twaDeg is the wind's bearing relative to the bow, and the bow is
        // drawn straight up - so the same number is the rotation.
        .rotationEffect(.degrees(plan.twaDeg))
    }

    private var boat: some View {
        BoatHull()
            .fill(Color.primary.opacity(0.85))
            .overlay(
                BoatHull().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
            )
            .frame(width: size * 0.20, height: size * 0.46)
            // Sails set on the side away from the wind: on port tack the
            // breeze is over the port side, so the boom is out to starboard.
            .overlay(alignment: .center) {
                Rectangle()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 1.8, height: size * 0.26)
                    .offset(y: size * 0.03)
                    .rotationEffect(
                        .degrees(boomAngle),
                        anchor: .top
                    )
            }
    }

    /// How far the boom is eased, and to which side. Sheeted in hard on the
    /// wind, squared off downwind, always opposite the breeze.
    private var boomAngle: Double {
        let magnitude = min(abs(plan.twaDeg), 170)
        let ease = (magnitude / 180) * 80
        return plan.tack == .port ? ease : -ease
    }
}

/// A simple hull outline, bow at the top.
private struct BoatHull: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.62),
            control1: CGPoint(x: w * 0.86, y: h * 0.18),
            control2: CGPoint(x: w, y: h * 0.40)
        )
        path.addLine(to: CGPoint(x: w * 0.86, y: h))
        path.addLine(to: CGPoint(x: w * 0.14, y: h))
        path.addLine(to: CGPoint(x: 0, y: h * 0.62))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: 0, y: h * 0.40),
            control2: CGPoint(x: w * 0.14, y: h * 0.18)
        )
        path.closeSubpath()
        return path
    }
}
