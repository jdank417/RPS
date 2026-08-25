//
//  MarkColor.swift
//  RPS
//
//  Buoy-color classification, ported from the reference app's
//  `mark-icon.util.ts`. Classifies a mark's real on-the-water color from its
//  charted light characteristic (e.g. `R N "2"`, `G C "1"`, `RG "FR"...`).
//  Follows standard USCG/IALA-B lateral buoyage notation: a leading R/G is a
//  plain red/green mark, RG/GR is a two-color junction (preferred-channel)
//  mark, RW is a red-and-white safe-water mark, Y is a yellow special mark.
//  Portable marks (RC-placed pins) have no charted color, so they stay
//  neutral.
//

import SwiftUI

enum MarkColor: Equatable {
    case neutral
    case red
    case green
    case yellow
    case orange
    case white
    case safeWater
    case junction(top: LateralColor, bottom: LateralColor)

    enum LateralColor { case red, green }

    static func classify(govtLight: String?, isPortable: Bool) -> MarkColor {
        guard !isPortable, let govtLight, !govtLight.isEmpty else { return .neutral }
        let s = govtLight.trimmingCharacters(in: .whitespaces).uppercased()
        let prefix = String(s.prefix { $0.isLetter })

        if prefix == "RG" || prefix == "GR" {
            return .junction(
                top: prefix.first == "R" ? .red : .green,
                bottom: prefix.dropFirst().first == "R" ? .red : .green
            )
        }
        if prefix == "RW" || prefix == "WR" { return .safeWater }
        if prefix.hasPrefix("R") { return .red }
        if prefix.hasPrefix("G") { return .green }
        if prefix == "Y" { return .yellow }
        if prefix == "W" || prefix == "WHT" {
            return s.contains("OR") ? .orange : .white
        }
        if s.contains("ORANGE") { return .orange }
        // No leading color letter (e.g. a bare light characteristic like "13"
        // QG) — fall back to the flash color if the rhythm names one
        // explicitly.
        if wordBoundaryContains(s, "QG") { return .green }
        if wordBoundaryContains(s, "QR") { return .red }
        return .neutral
    }

    private static func wordBoundaryContains(_ s: String, _ token: String) -> Bool {
        s.range(of: "\\b\(token)\\b", options: .regularExpression) != nil
    }

    var label: String {
        switch self {
        case .red: return "red"
        case .green: return "green"
        case .yellow: return "yellow"
        case .orange: return "orange"
        case .white: return "white"
        case .safeWater: return "red/white"
        case .junction(let top, let bottom): return "\(top == .red ? "red" : "green")/\(bottom == .red ? "red" : "green") junction"
        case .neutral: return ""
        }
    }

    /// Solid background swatch color for badges that don't need the striped
    /// safe-water or split junction rendering.
    var solid: Color {
        switch self {
        case .red: return Color(red: 0.816, green: 0.125, blue: 0.122)
        case .green: return Color(red: 0.086, green: 0.478, blue: 0.239)
        case .yellow: return Color(red: 0.910, green: 0.706, blue: 0)
        case .orange: return Color(red: 0.886, green: 0.475, blue: 0.122)
        case .white: return Color(white: 0.957)
        case .safeWater: return Color(red: 0.816, green: 0.125, blue: 0.122)
        case .junction(let top, _): return top == .red ? MarkColor.red.solid : MarkColor.green.solid
        case .neutral: return Color(red: 0.114, green: 0.435, blue: 0.647)
        }
    }

    var foreground: Color {
        switch self {
        case .yellow, .white: return .black.opacity(0.85)
        default: return .white
        }
    }
}
