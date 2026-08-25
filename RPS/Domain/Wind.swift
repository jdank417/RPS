//
//  Wind.swift
//  RPS
//
//  Forecast wind, ported from the reference app's `wind.service.ts`. This is
//  model wind at 10 metres from a public forecast service - not a masthead
//  reading - which is why every place it's shown in the UI must say
//  "forecast" rather than presenting it as ground truth. Close to shore, in a
//  sea breeze, or anywhere with a headland upwind it can be wrong by a long
//  way; what it's good for is the thing a sailor can't get from GPS alone -
//  roughly which way the breeze is going, for tack/point-of-sail readouts.
//
//  This file holds the pure, network-free pieces (types, throttling and
//  staleness decisions); the actual fetch lives in `WindService`.
//

import Foundation

struct WindReading: Codable, Equatable {
    /// Direction the wind is blowing *from*, degrees true - the convention
    /// every forecast and masthead readout uses.
    var fromDeg: Double
    var speedKts: Double
    var gustKts: Double?
    /// When the forecast was fetched (epoch seconds), so the UI can admit how
    /// old it is.
    var at: Date
}

enum Wind {
    /// Model wind updates roughly quarter-hourly, so asking more often than
    /// this spends battery and cellular data for the same answer.
    static let refreshInterval: TimeInterval = 10 * 60
    /// Far enough that the forecast grid cell has probably changed.
    static let movedNm: Double = 3
    /// Past this the reading is too old to steer by and is shown as stale.
    static let staleInterval: TimeInterval = 60 * 60

    /// Whether a fresh fetch is worth making, given when/where the last one
    /// happened. Called on every GPS fix - roughly once a second - so the
    /// decision not to fetch is the common path and has to be cheap.
    static func shouldRefresh(
        now: Date, lastFetchAt: Date?, lastLat: Double?, lastLon: Double?, lat: Double, lon: Double
    ) -> Bool {
        let moved: Bool
        if let lastLat, let lastLon {
            moved = GeoMath.haversineNm(lat1: lastLat, lon1: lastLon, lat2: lat, lon2: lon) > movedNm
        } else {
            moved = true
        }
        guard let lastFetchAt else { return true }
        if !moved && now.timeIntervalSince(lastFetchAt) < refreshInterval { return false }
        return true
    }

    static func isStale(_ reading: WindReading, now: Date) -> Bool {
        now.timeIntervalSince(reading.at) > staleInterval
    }

    /// "12 min ago", for a reading that isn't fresh.
    static func ageText(_ reading: WindReading, now: Date) -> String {
        let mins = Int((now.timeIntervalSince(reading.at) / 60).rounded())
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins) min ago" }
        let hrs = Int((Double(mins) / 60).rounded())
        if hrs < 24 { return "\(hrs)h ago" }
        return "\(Int((Double(hrs) / 24).rounded()))d ago"
    }
}
