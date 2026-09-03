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
    /// Nil means the waiver gate should show before anything else in the
    /// app. Kept as the raw ISO 8601 string rather than `Date` - nothing
    /// in the app needs to read the timestamp itself, only whether it's
    /// present, and the shared decoder has no date strategy configured.
    var liabilityWaiverAcceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case homeClubId = "home_club_id"
        case isActive = "is_active"
        case isSuperuser = "is_superuser"
        case liabilityWaiverAcceptedAt = "liability_waiver_accepted_at"
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
