//
//  MarkBadge.swift
//  RPS
//
//  A small circular badge showing a mark's code, colored by its charted
//  light characteristic (or neutral for a portable mark), with an optional
//  rounding tag and start ring — used in the course list, the map, and the
//  leg navigator so a mark reads the same everywhere in the app.
//

import SwiftUI

struct MarkBadge: View {
    let code: String
    let govtLight: String?
    let portable: Bool
    var rounding: Rounding? = nil
    var isStart: Bool = false
    var size: CGFloat = 36

    private var color: MarkColor { .classify(govtLight: govtLight, isPortable: portable) }

    var body: some View {
        ZStack {
            swatch
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                .overlay {
                    if isStart {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-3)
                    }
                }

            Text(code)
                .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                .foregroundStyle(color.foreground)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(2)

            if let rounding {
                roundingTag(rounding)
                    .offset(x: size * 0.36, y: size * 0.36)
            }
        }
        .frame(width: size + 8, height: size + 8)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var swatch: some View {
        switch color {
        case .safeWater:
            StripedFill(color: color.solid)
        case .junction(let top, let bottom):
            VStack(spacing: 0) {
                (top == .red ? MarkColor.red.solid : MarkColor.green.solid)
                (bottom == .red ? MarkColor.red.solid : MarkColor.green.solid)
            }
        default:
            color.solid
        }
    }

    private func roundingTag(_ rounding: Rounding) -> some View {
        Text(rounding.rawValue)
            .font(.system(size: size * 0.26, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size * 0.5, height: size * 0.5)
            .background(rounding == .starboard ? MarkColor.green.solid : MarkColor.red.solid)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1))
    }

    private var accessibilityText: String {
        var parts = [code]
        if !color.label.isEmpty { parts.append(color.label) }
        if let rounding { parts.append(roundingWord(rounding)) }
        if isStart { parts.append("start") }
        return parts.joined(separator: ", ")
    }
}

private struct StripedFill: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let stripe: CGFloat = max(geo.size.width / 6, 4)
            HStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { i in
                    (i % 2 == 0 ? color : Color.white)
                        .frame(width: stripe)
                }
            }
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        MarkBadge(code: "A", govtLight: "R N \"2\"", portable: false)
        MarkBadge(code: "H", govtLight: "G C \"1\"", portable: false, rounding: .starboard, isStart: true)
        MarkBadge(code: "RG", govtLight: "RG \"FR\"", portable: false)
        MarkBadge(code: "RW", govtLight: "RW", portable: false)
        MarkBadge(code: "St", govtLight: nil, portable: true, rounding: .port)
    }
    .padding()
}
