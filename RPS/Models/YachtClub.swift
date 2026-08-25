//
//  YachtClub.swift
//  RPS
//

import Foundation

struct YachtClub: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var slug: String
    var name: String
    var region: String?
    var country: String?
    /// Inline SVG markup, or nil. An initials-badge fallback is used in the
    /// UI rather than rendering raw SVG for v1.
    var burgeeSvg: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, region, country
        case burgeeSvg = "burgee_svg"
    }

    /// Two-letter fallback badge when there's no burgee artwork to show.
    var initials: String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
