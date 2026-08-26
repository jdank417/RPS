//
//  APICacheTests.swift
//  RPSTests
//
//  Covers the cache's invalidation rules. These exist because of a real
//  bug: a mark list deleted in the admin console kept appearing on the
//  phone, because reference data was served cache-first behind a long TTL.
//  The fix moved fetching to network-first, but the cache still has to
//  forget things at the right moments or a retired list's buoys can come
//  back the next time its id is asked for.
//

import Testing
import Foundation
@testable import RPS

@MainActor
private func makeCache() -> (APICache, UserDefaults) {
    // A throwaway suite per test so cases can't see each other's writes.
    let name = "rps.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (APICache(defaults: defaults), defaults)
}

private func makeList(_ name: String, id: UUID = UUID()) -> MarkList {
    MarkList(id: id, name: name, slug: name.lowercased(), scope: .club, ownerClubId: nil, sourceLabel: nil)
}

private func makeMark(_ code: String, listId: UUID) -> Mark {
    Mark(
        id: UUID(), markListId: listId, code: code, name: "Mark \(code)",
        govtLight: nil, lat: 42.5, lon: -70.8, govNumber: nil,
        portable: false, notes: nil, displayOrder: 0
    )
}

@Suite("APICache invalidation")
struct APICacheTests {

    @MainActor
    @Test("Marks survive a list-index refresh that still contains their list")
    func marksSurviveWhenListStillPresent() {
        let (cache, _) = makeCache()
        let list = makeList("Wednesday")
        cache.setMarkLists([list], clubSlug: "byc")
        cache.setMarks([makeMark("A", listId: list.id)], markListId: list.id)

        // Same list still there on the next fetch.
        cache.setMarkLists([list], clubSlug: "byc")

        #expect(cache.getMarks(markListId: list.id)?.count == 1)
    }

    @MainActor
    @Test("A list dropped from the index takes its cached marks with it")
    func deletedListDropsItsMarks() {
        let (cache, _) = makeCache()
        let kept = makeList("Wednesday")
        let deleted = makeList("Scratch")
        cache.setMarkLists([kept, deleted], clubSlug: "byc")
        cache.setMarks([makeMark("A", listId: kept.id)], markListId: kept.id)
        cache.setMarks([makeMark("Z", listId: deleted.id)], markListId: deleted.id)

        // The club admin deletes "Scratch"; the next index fetch omits it.
        cache.setMarkLists([kept], clubSlug: "byc")

        #expect(cache.getMarks(markListId: deleted.id) == nil)
        #expect(cache.getMarks(markListId: kept.id)?.count == 1)
    }

    @MainActor
    @Test("forgetMarks drops exactly one list")
    func forgetMarksIsScoped() {
        let (cache, _) = makeCache()
        let a = makeList("A"), b = makeList("B")
        cache.setMarks([makeMark("1", listId: a.id)], markListId: a.id)
        cache.setMarks([makeMark("2", listId: b.id)], markListId: b.id)

        cache.forgetMarks(markListId: a.id)

        #expect(cache.getMarks(markListId: a.id) == nil)
        #expect(cache.getMarks(markListId: b.id)?.count == 1)
    }

    @MainActor
    @Test("clearAll wipes every cached response")
    func clearAllWipesEverything() {
        let (cache, _) = makeCache()
        let list = makeList("Wednesday")
        cache.setClubs([YachtClub(id: UUID(), slug: "byc", name: "BYC", region: nil, country: nil, burgeeSvg: nil)])
        cache.setMarkLists([list], clubSlug: "byc")
        cache.setMarks([makeMark("A", listId: list.id)], markListId: list.id)

        cache.clearAll()

        #expect(cache.getClubs() == nil)
        #expect(cache.getMarkLists(clubSlug: "byc") == nil)
        #expect(cache.getMarks(markListId: list.id) == nil)
    }

    @MainActor
    @Test("Stale bootstrap is readable regardless of age, for the launch path")
    func staleBootstrapIsReadable() {
        let (cache, _) = makeCache()
        let user = User(
            id: UUID(), email: "a@b.com", fullName: nil,
            homeClubId: nil, isActive: true, isSuperuser: false
        )
        let payload = Bootstrap(
            user: user, clubs: [], club: nil, markLists: [],
            selectedMarkListId: nil, marks: []
        )
        cache.setBootstrap(payload)

        #expect(cache.getStaleBootstrap()?.user.email == "a@b.com")
    }
}
