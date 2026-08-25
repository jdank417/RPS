//
//  Mark.swift
//  RPS
//
//  A charted or portable racing mark. lat/lon both nil means a portable mark
//  with no fixed charted position - its course position must come from a GPS
//  ping or manual lat/lon entry at course-build time, never assumed.
//

import Foundation

struct Mark: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var markListId: UUID
    var code: String
    var name: String
    var govtLight: String?
    var lat: Double?
    var lon: Double?
    var govNumber: String?
    var portable: Bool
    var notes: String?
    var displayOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, code, name, lat, lon, portable, notes
        case markListId = "mark_list_id"
        case govtLight = "govt_light"
        case govNumber = "gov_number"
        case displayOrder = "display_order"
    }

    /// A synthetic placeholder mark used when the course builder needs a
    /// start entry that doesn't correspond to anything in the club's list.
    static func syntheticStart() -> Mark {
        Mark(
            id: UUID(),
            markListId: UUID(),
            code: "St",
            name: "Start (set position)",
            govtLight: nil,
            lat: nil,
            lon: nil,
            govNumber: nil,
            portable: true,
            notes: nil,
            displayOrder: -1
        )
    }
}
