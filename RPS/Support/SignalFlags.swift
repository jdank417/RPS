//
//  SignalFlags.swift
//  RPS
//
//  The two signals the RC actually flies, drawn as cloth rather than
//  described in words. Ported from the reference web app's "signals" row,
//  which is what sailors on this app were already used to reading.
//
//  A rounding is not really a setting - it is a flag on the committee boat,
//  and the sailor's job is to look at it and match it. Drawing the same
//  colour cloth here means the check is a glance rather than a translation.
//

import SwiftUI

/// The RC's course-wide rounding signal: green cloth for "leave all marks to
/// starboard", red for port, blank grey when nothing is signalled.
struct RoundingFlagCloth: View {
    let rounding: Rounding?
    var width: CGFloat = 30
    var height: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(.black.opacity(0.15), lineWidth: 1)
            )
    }

    private var fill: Color {
        switch rounding {
        case .starboard: return Color(red: 0.086, green: 0.478, blue: 0.239) // buoy green
        case .port: return Color(red: 0.816, green: 0.126, blue: 0.122)      // buoy red
        case nil: return Color(uiColor: .systemGray4)
        }
    }
}

/// Code flag T - red / white / blue vertical bands - flown for "twice
/// around". Dimmed and desaturated while it is down, so "is T flying?" is
/// answerable without reading the label.
struct CodeFlagT: View {
    let flying: Bool
    var width: CGFloat = 30
    var height: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            Color(red: 0.816, green: 0.126, blue: 0.122)
            Color.white
            Color(red: 0.114, green: 0.310, blue: 0.612)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(.black.opacity(0.15), lineWidth: 1)
        )
        .saturation(flying ? 1 : 0.4)
        .opacity(flying ? 1 : 0.35)
    }
}

/// One tappable signal: cloth on the left, what it means on the right.
struct SignalButton<Cloth: View>: View {
    let caption: String
    let isActive: Bool
    var activeColor: Color = .accentColor
    @ViewBuilder let cloth: () -> Cloth
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                cloth()
                Text(caption)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 44pt: this gets pressed on a moving boat.
            .frame(minHeight: 44)
            .padding(.horizontal, 10)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? activeColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The per-mark rounding tag on a course row: S, P, or a dash when nothing
/// is set. Shown hollow when the mark is only inheriting the RC's
/// course-wide signal rather than carrying one of its own - the difference
/// matters when the RC changes the general signal.
struct RoundingTag: View {
    let rounding: Rounding?
    let isInherited: Bool

    var body: some View {
        Text(label)
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(isInherited ? tint : .white)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isInherited ? tint.opacity(0.14) : tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(isInherited ? 0.55 : 0), lineWidth: 1.5)
            )
    }

    private var label: String {
        switch rounding {
        case .starboard: return "S"
        case .port: return "P"
        case nil: return "–"
        }
    }

    private var tint: Color {
        switch rounding {
        case .starboard: return Color(red: 0.086, green: 0.478, blue: 0.239)
        case .port: return Color(red: 0.816, green: 0.126, blue: 0.122)
        case nil: return Color(uiColor: .systemGray)
        }
    }
}

/// Direction of travel along a leg, drawn at the leg's midpoint.
///
/// A course line on its own is ambiguous - the same line is sailed in
/// opposite directions on different legs of a windward-leeward, and reading
/// which way round the course goes off the mark order is exactly the kind of
/// thing that goes wrong under pressure.
struct LegDirectionArrow: View {
    let isActive: Bool

    var body: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: isActive ? 15 : 12, weight: .black))
            .foregroundStyle(isActive ? Color.orange : Color.accentColor)
            .shadow(color: .white.opacity(0.9), radius: 1)
            .shadow(color: .black.opacity(0.25), radius: 1.5)
    }
}
