//
//  Bootstrap.swift
//  RPS
//
//  The course builder's whole startup payload, fetched in one request. See
//  the reference backend's bootstrap.py for why this exists: collapsing
//  three dependent round trips (clubs -> mark lists -> marks) into one.
//

import Foundation

struct Bootstrap: Codable, Equatable {
    var user: User
    var clubs: [YachtClub]
    var club: YachtClub?
    var markLists: [MarkList]
    var selectedMarkListId: UUID?
    var marks: [Mark]

    enum CodingKeys: String, CodingKey {
        case user, clubs, club
        case markLists = "mark_lists"
        case selectedMarkListId = "selected_mark_list_id"
        case marks
    }
}
