//
//  APICache.swift
//  RPS
//
//  Lightweight TTL cache for API responses, backed by UserDefaults. Avoids
//  redundant network calls for slow-changing reference data (clubs, mark
//  lists, marks) while still allowing pull-to-refresh as a manual override.
//

import Foundation

struct CachedResponse<T: Codable>: Codable {
    let data: T
    let cachedAt: Date
    
    func isExpired(maxAge: TimeInterval) -> Bool {
        Date().timeIntervalSince(cachedAt) > maxAge
    }
}

@MainActor
final class APICache {
    static let shared = APICache()
    
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Cache TTLs
    private let clubsTTL: TimeInterval = 3600 * 4 // 4 hours
    private let markListsTTL: TimeInterval = 3600 * 4 // 4 hours
    private let marksTTL: TimeInterval = 3600 * 4 // 4 hours
    private let bootstrapTTL: TimeInterval = 60 * 5 // 5 minutes
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    // MARK: - Generic cache operations
    
    private func key(for identifier: String) -> String {
        "rps.api.cache.\(identifier)"
    }
    
    func get<T: Codable>(_ identifier: String, maxAge: TimeInterval) -> T? {
        guard let data = defaults.data(forKey: key(for: identifier)),
              let cached = try? decoder.decode(CachedResponse<T>.self, from: data),
              !cached.isExpired(maxAge: maxAge) else {
            return nil
        }
        return cached.data
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
    
    func invalidateAll() {
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("rps.api.cache.") }
        allKeys.forEach { defaults.removeObject(forKey: $0) }
    }
    
    // MARK: - Specific cache accessors
    
    func getClubs() -> [YachtClub]? {
        get("clubs", maxAge: clubsTTL)
    }
    
    func setClubs(_ clubs: [YachtClub]) {
        set(clubs, for: "clubs")
    }
    
    func getMarkLists(clubSlug: String) -> [MarkList]? {
        get("markLists.\(clubSlug)", maxAge: markListsTTL)
    }
    
    func setMarkLists(_ lists: [MarkList], clubSlug: String) {
        set(lists, for: "markLists.\(clubSlug)")
    }
    
    func getMarks(markListId: UUID) -> [Mark]? {
        get("marks.\(markListId.uuidString)", maxAge: marksTTL)
    }
    
    func setMarks(_ marks: [Mark], markListId: UUID) {
        set(marks, for: "marks.\(markListId.uuidString)")
    }
    
    func getBootstrap(clubSlug: String?) -> Bootstrap? {
        let key = clubSlug ?? "default"
        return get("bootstrap.\(key)", maxAge: bootstrapTTL)
    }
    
    func setBootstrap(_ bootstrap: Bootstrap, clubSlug: String?) {
        let key = clubSlug ?? "default"
        set(bootstrap, for: "bootstrap.\(key)")
    }
}
