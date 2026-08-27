//
//  WindFlowOverlay.swift
//  RPS
//
//  A drifting field of comet streaks over the chart, showing which way the
//  breeze is going.
//
//  Drawn as one Canvas over the map rather than as map annotations. Three
//  reasons, in order of how much they mattered:
//
//  1. Discrete arrows read as objects - things placed *on* the chart, at
//     odds with the marks and legs that genuinely are. A field of faint
//     tapered streaks reads as weather: ambient, behind everything, clearly
//     not something you sail to.
//  2. A Canvas draws the whole field in one pass. The same number of map
//     annotations would be that many SwiftUI subtrees over a map already
//     re-laying out marks and polylines - which is what makes a field dense
//     enough to read as weather affordable at all.
//  3. Wind here is a single direction for the whole visible area - it comes
//     from one forecast sample, not a grid - so nothing is lost by drawing
//     it in screen space. Pretending otherwise by geo-anchoring each particle
//     would imply a spatial resolution the data doesn't have.
//

import SwiftUI

struct WindFlowOverlay: View {
    /// Direction the wind is blowing *from*, degrees true.
    let windFromDeg: Double
    /// The map's rotation, so the flow stays true when the chart is turned.
    let cameraHeading: Double

    /// Seconds for a particle to cross its full travel.
    private let period: Double = 3.8
    private let particleCount = 130

    var body: some View {
        // 30fps: fast enough to read as motion, and this runs for as long as
        // the overlay is up on a phone that has to last a whole race.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            Canvas { context, size in
                draw(
                    in: &context,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        // Screen-space direction the wind travels: meteorological "from"
        // plus 180, less however far the map itself is rotated.
        let angle = (windFromDeg + 180 - cameraHeading) * .pi / 180
        let dx = sin(angle)
        let dy = -cos(angle)

        // Travel far enough that particles are always entering from off
        // screen rather than appearing inside it.
        let travel = (size.width + size.height) * 0.75
        let streak: CGFloat = 22

        for i in 0..<particleCount {
            // Deterministic scatter - a fixed field rather than one that
            // reshuffles every frame.
            let seedA = Self.hashToUnit(i &* 2_654_435_761)
            let seedB = Self.hashToUnit(i &* 40_503 &+ 17)
            let seedC = Self.hashToUnit(i &* 92_837_111 &+ 3)

            let progress = ((time / period) + seedC).truncatingRemainder(dividingBy: 1)

            // Start off the upwind edge and run across.
            let originX = seedA * (size.width + travel) - travel / 2
            let originY = seedB * (size.height + travel) - travel / 2
            let advance = (progress - 0.5) * travel

            let headX = originX + dx * advance
            let headY = originY + dy * advance
            let head = CGPoint(x: headX, y: headY)
            let tail = CGPoint(x: headX - dx * streak, y: headY - dy * streak)

            // Fade in and out across the run so streaks stream past rather
            // than blink into existence.
            let fade = sin(progress * .pi)
            guard fade > 0.02 else { continue }

            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)

            // The comet is what makes it directional without an arrowhead:
            // transparent at the tail, brightest at the head.
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.teal.opacity(0),
                        Color.teal.opacity(0.5 * fade),
                    ]),
                    startPoint: tail,
                    endPoint: head
                ),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
            )

            // A small bright tip, so the leading end is unambiguous even
            // where streaks cross the course lines.
            context.fill(
                Path(ellipseIn: CGRect(x: head.x - 1.2, y: head.y - 1.2, width: 2.4, height: 2.4)),
                with: .color(Color.teal.opacity(0.7 * fade))
            )
        }
    }

    /// A cheap deterministic 0..1 from an integer seed. Not good randomness -
    /// it only has to scatter points without visible banding, and being
    /// deterministic is the point: the field must not reshuffle on every
    /// redraw.
    private static func hashToUnit(_ value: Int) -> CGFloat {
        var x = UInt64(bitPattern: Int64(value &* 2_246_822_519))
        x ^= x >> 33
        x = x &* 0xff51_afd7_ed55_8ccd
        x ^= x >> 33
        return CGFloat(Double(x % 100_000) / 100_000.0)
    }
}
