//
//  User.swift
//  RPS
//

import Foundation

struct User: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var email: String
    var fullName: String?
    var homeClubId: UUID?
    var isActive: Bool
    var isSuperuser: Bool

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case homeClubId = "home_club_id"
        case isActive = "is_active"
        case isSuperuser = "is_superuser"
    }
}

/// Body for `PATCH /users/me`. Both fields are optional on the wire; omit a
/// field here (leave it `nil`) to leave that property unchanged server-side.
struct UserUpdate: Encodable {
    var fullName: String?
    var homeClubId: UUID?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case homeClubId = "home_club_id"
    }
}
