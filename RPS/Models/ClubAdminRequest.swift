//
//  ClubAdminRequest.swift
//  RPS
//
//  A sailor asking to be made an admin of a club that's already on the
//  platform. Mirrors rps_admin's ClubAdminRequest — reviewed by either that
//  club's existing admins or a superuser, from the web console.
//

import Foundation

enum ClubAdminRequestStatus: String, Codable {
    case pending
    case approved
    case rejected
}

struct ClubAdminRequest: Codable, Identifiable, Equatable {
    let id: UUID
    var clubId: UUID
    var clubName: String
    var clubSlug: String
    var message: String?
    var status: ClubAdminRequestStatus
    var reviewNote: String?

    enum CodingKeys: String, CodingKey {
        case id
        case clubId = "club_id"
        case clubName = "club_name"
        case clubSlug = "club_slug"
        case message, status
        case reviewNote = "review_note"
    }
}

struct ClubAdminRequestCreate: Encodable {
    var message: String?
}
