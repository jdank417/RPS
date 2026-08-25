//
//  APICache.swift
//  RPS
//
//  Lightweight TTL cache for API responses, backed by UserDefaults.
//
//  Two jobs, and the second one matters more than it looks:
//
//  1. Avoid re-fetching slow-changing reference data (clubs, mark lists,
//     marks) on every tab switch. That data only changes when a club admin
//     edits it in the web console.
//  2. Let the app show something real the instant it launches. The backend
//     is on a free tier that sleeps after 15 minutes idle, so a cold request
//     can take the better part of a minute - blocking the whole app behind
//     that is what made launch feel broken. Reading the last known payload
//     first and revalidating behind it turns that into an instant launch.
//
//  Everything cached here is per-account data, so `clearAll()` MUST be
//  called on sign-out - see AppState.signOut().
//

import Foundation

struct CachedResponse<T: Codable>: Codable {
    let data: T
    let cachedAt: Date

    func age() -> TimeInterval { Date().timeIntervalSince(cachedAt) }
    func isExpired(maxAge: TimeInterval) -> Bool { age() > maxAge }
}

@MainActor
final class APICache {
    static let shared = APICache()

    private static let keyPrefix = "rps.api.cache."

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Reference data: clubs, mark lists and marks change only when a club
    /// admin edits them in the web console, so a long TTL is safe. Pull to
    /// refresh is the manual override.
    private let referenceTTL: TimeInterval = 60 * 60 * 12

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Generic

    private func key(for identifier: String) -> String { Self.keyPrefix + identifier }

    func get<T: Codable>(_ identifier: String, maxAge: TimeInterval) -> T? {
        guard let entry: CachedResponse<T> = entry(identifier), !entry.isExpired(maxAge: maxAge) else {
            return nil
        }
        return entry.data
    }

    /// Reads regardless of age. Used for the launch path, where a stale
    /// payload shown immediately (and refreshed behind) beats a spinner.
    func getStale<T: Codable>(_ identifier: String) -> T? {
        entry(identifier)?.data
    }

    private func entry<T: Codable>(_ identifier: String) -> CachedResponse<T>? {
        guard let data = defaults.data(forKey: key(for: identifier)) else { return nil }
        return try? decoder.decode(CachedResponse<T>.self, from: data)
    }

    func set<T: Codable>(_ value: T, for identifier: String) {
        let cached = CachedResponse(data: value, cachedAt: Date())
        if let data = try? encoder.encode(cached) {
            defaults.set(data, forKey: key(for: identifier))
        }
    }

    func invalidate(_ identifier: String) {
        defaults.removeObject(forKey: key(for: identifier))
    }

    /// Drops every cached response. Called on sign-out: all of this is
    /// per-account data, and leaving it behind would show the next person to
    /// sign in on this phone the previous account's clubs and bootstrap.
    func clearAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Typed accessors

    func getClubs() -> [YachtClub]? { get("clubs", maxAge: referenceTTL) }
    func setClubs(_ clubs: [YachtClub]) { set(clubs, for: "clubs") }

    func getMarkLists(clubSlug: String) -> [MarkList]? {
        get("markLists.\(clubSlug)", maxAge: referenceTTL)
    }
    func setMarkLists(_ lists: [MarkList], clubSlug: String) {
        set(lists, for: "markLists.\(clubSlug)")
    }

    func getMarks(markListId: UUID) -> [Mark]? {
        get("marks.\(markListId.uuidString)", maxAge: referenceTTL)
    }
    func setMarks(_ marks: [Mark], markListId: UUID) {
        set(marks, for: "marks.\(markListId.uuidString)")
    }

    // MARK: - Bootstrap

    /// Bootstrap carries live account state (who you are, your home club), so
    /// it is never served from cache as if it were fresh - it is only read
    /// back deliberately, by the launch path, via `getStaleBootstrap`.
    ///
    /// Stored under one key rather than one per club slug: the app only ever
    /// has a single active bootstrap, and launch needs "whatever was loaded
    /// last" without knowing which club that was. The club it belongs to is
    /// inside the payload.
    private static let bootstrapKey = "bootstrap.latest"

    func getStaleBootstrap() -> Bootstrap? {
        getStale(Self.bootstrapKey)
    }

    func setBootstrap(_ bootstrap: Bootstrap) {
        set(bootstrap, for: Self.bootstrapKey)
    }
}
