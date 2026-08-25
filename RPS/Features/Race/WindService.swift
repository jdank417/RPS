//
//  WindService.swift
//  RPS
//
//  Forecast wind fetched directly from the public Open-Meteo API (no key
//  needed), ported from the reference app's `wind.service.ts`. Throttled by
//  time-since-last-fetch and distance-moved (`Wind.shouldRefresh`), cached
//  locally with an honest stale/age indicator, and labeled everywhere in the
//  UI as forecast/model wind — never presented as a live masthead reading.
//

import Foundation
import Observation

@Observable
@MainActor
final class WindService {

    private static let cacheKey = "rps.cache.wind"
    private static let endpoint = "https://api.open-meteo.com/v1/forecast"

    var wind: WindReading?
    var error: String?

    private var lastFetchAt: Date?
    private var lastLat: Double?
    private var lastLon: Double?
    private var inFlight = false

    private let session: URLSession
    private let now: () -> Date

    init(session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(WindReading.self, from: data) {
            wind = cached
        }
    }

    var stale: Bool {
        guard let wind else { return false }
        return Wind.isStale(wind, now: now())
    }

    var ageText: String {
        guard let wind else { return "" }
        return Wind.ageText(wind, now: now())
    }

    /// Refreshes if it's worth refreshing. Called on every GPS fix — roughly
    /// once a second — so the decision not to fetch is the common path and
    /// has to be cheap and obviously correct.
    func refresh(lat: Double, lon: Double) async {
        guard !inFlight else { return }
        let nowDate = now()
        guard Wind.shouldRefresh(now: nowDate, lastFetchAt: lastFetchAt, lastLat: lastLat, lastLon: lastLon, lat: lat, lon: lon) else {
            return
        }

        inFlight = true
        defer { inFlight = false }

        var components = URLComponents(string: Self.endpoint)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
            URLQueryItem(name: "current", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
        ]
        guard let url = components.url else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            guard let speed = decoded.current?.windSpeed10m, let direction = decoded.current?.windDirection10m else {
                throw URLError(.cannotParseResponse)
            }
            let reading = WindReading(fromDeg: direction, speedKts: speed, gustKts: decoded.current?.windGusts10m, at: nowDate)
            wind = reading
            error = nil
            if let data = try? JSONEncoder().encode(reading) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
            lastFetchAt = reading.at
            lastLat = lat
            lastLon = lon
        } catch {
            // Keep whatever was cached — a stale breeze clearly labeled beats
            // a blank readout, and losing signal offshore is normal rather
            // than exceptional.
            self.error = "No forecast wind — showing the last one received."
            // Back off so a boat with no signal isn't retrying every second.
            lastFetchAt = nowDate
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let windSpeed10m: Double?
        let windDirection10m: Double?
        let windGusts10m: Double?

        enum CodingKeys: String, CodingKey {
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case windGusts10m = "wind_gusts_10m"
        }
    }
    let current: Current?
}
