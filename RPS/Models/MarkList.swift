//
//  MarkList.swift
//  RPS
//

import Foundation

enum MarkListScope: String, Codable {
    case club
    case regional
}

struct MarkList: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var slug: String
    var scope: MarkListScope
    var ownerClubId: UUID?
    var sourceLabel: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, scope
        case ownerClubId = "owner_club_id"
        case sourceLabel = "source_label"
    }
}
