//
//  TidalCurrentService.swift
//  RPS
//
//  Water current - set and drift - from NOAA's CO-OPS current-predictions
//  service, the tactical factor wind alone doesn't cover: which way the
//  water itself is moving, and how fast. NOAA's current stations sit in
//  specific channels and harbors rather than a grid, so this finds the
//  nearest one to the boat and says so, including how far away it is -
//  a station 20nm off isn't standing in for the water under the boat.
//
//  LOWER CONFIDENCE THAN THE REST OF THIS APP'S NETWORKING CODE: this talks
//  to NOAA's public CO-OPS API, which (unlike WeatherKit) has no official
//  Apple documentation to check code against - what's here was
//  reconstructed from NOAA's own web-services page and third-party client
//  source code, not verified against a live response, because this
//  environment's network egress blocks api.tidesandcurrents.noaa.gov and
//  tidesandcurrents.noaa.gov outright. The parsing is deliberately
//  defensive (tolerant of a couple of plausible key names and of numeric
//  fields arriving as either JSON numbers or strings) for exactly that
//  reason. Please verify this one on-device before trusting it.
//

import Foundation
import Observation

/// One hour's predicted current.
struct TidalCurrentPoint: Identifiable, Equatable {
    var date: Date
    /// Direction the water is flowing *toward*, degrees true. NOAA's own
    /// convention for current - the opposite sense from wind, which is
    /// always given as the direction it's blowing *from*.
    var towardDeg: Double
    var speedKts: Double

    var id: Date { date }
}

struct TidalCurrentSnapshot: Equatable {
    var stationName: String
    var stationDistanceNm: Double
    /// The next several hours, same shape as `RaceWeatherSnapshot.hourly` -
    /// the first point is the current reading.
    var points: [TidalCurrentPoint]

    var current: TidalCurrentPoint? { points.first }
}

@Observable
@MainActor
final class TidalCurrentService {

    private struct Station: Decodable {
        var id: String
        var name: String
        var lat: Double
        var lng: Double

        private enum CodingKeys: String, CodingKey { case id, name, lat, lng }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try Self.string(c, .id)
            name = (try? c.decode(String.self, forKey: .name)) ?? "Unnamed station"
            lat = try Self.double(c, .lat)
            lng = try Self.double(c, .lng)
        }

        /// NOAA's station id looks numeric but isn't guaranteed to arrive
        /// as a JSON string rather than a JSON number - tolerate either.
        private static func string(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String {
            if let s = try? c.decode(String.self, forKey: key) { return s }
            if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not a station id")
        }

        private static func double(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Double {
            if let d = try? c.decode(Double.self, forKey: key) { return d }
            if let s = try? c.decode(String.self, forKey: key), let d = Double(s) { return d }
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not a coordinate")
        }
    }

    private struct StationsResponse: Decodable {
        var stations: [Station]
    }

    private static let stationsCacheKey = "rps.cache.currentStations"
    private static let stationsURL = "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=currentpredictions"
    private static let dataURL = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
    /// Past this, the nearest current station is too far from the boat to
    /// say anything useful about the water it's actually in.
    private static let maxUsefulDistanceNm: Double = 25

    private let session: URLSession
    private let now: () -> Date

    var snapshot: TidalCurrentSnapshot?
    var isLoading = false
    var error: String?

    private var cachedStations: [Station]?
    private var lastFetchAt: Date?
    private var lastLat: Double?
    private var lastLon: Double?

    init(session: URLSession = .shared, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.now = now
    }

    func shouldRefresh(lat: Double, lon: Double) -> Bool {
        guard let lastFetchAt else { return true }
        if let lastLat, let lastLon,
           GeoMath.haversineNm(lat1: lastLat, lon1: lastLon, lat2: lat, lon2: lon) > 3 {
            return true
        }
        // Current predictions turn over faster than wind - a 30-minute
        // window keeps the "now" reading from drifting stale mid-race.
        return now().timeIntervalSince(lastFetchAt) > 30 * 60
    }

    func refresh(lat: Double, lon: Double, force: Bool = false) async {
        guard force || shouldRefresh(lat: lat, lon: lon) else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let stations = try await loadStations()
            guard let nearest = nearestStation(in: stations, lat: lat, lon: lon) else {
                error = "No tidal current stations found."
                lastFetchAt = now()
                return
            }
            let distanceNm = GeoMath.haversineNm(lat1: lat, lon1: lon, lat2: nearest.lat, lon2: nearest.lng)
            guard distanceNm <= Self.maxUsefulDistanceNm else {
                error = "The nearest current station (\(nearest.name)) is \(Int(distanceNm.rounded())) nm away - too far to be useful here."
                snapshot = nil
                lastFetchAt = now()
                lastLat = lat
                lastLon = lon
                return
            }

            let points = try await fetchPredictions(stationId: nearest.id)
            guard !points.isEmpty else { throw URLError(.cannotParseResponse) }

            snapshot = TidalCurrentSnapshot(stationName: nearest.name, stationDistanceNm: distanceNm, points: points)
            error = nil
            lastFetchAt = now()
            lastLat = lat
            lastLon = lon
        } catch {
            self.error = "Couldn't load tidal current data (\(error.localizedDescription))."
            lastFetchAt = now()
        }
    }

    /// The station list barely changes - fetched once and cached, rather
    /// than re-downloaded (it can run to a few thousand entries) on every
    /// refresh.
    private func loadStations() async throws -> [Station] {
        if let cachedStations { return cachedStations }
        if let data = UserDefaults.standard.data(forKey: Self.stationsCacheKey),
           let decoded = try? JSONDecoder().decode(StationsResponse.self, from: data),
           !decoded.stations.isEmpty {
            cachedStations = decoded.stations
            return decoded.stations
        }
        guard let url = URL(string: Self.stationsURL) else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(StationsResponse.self, from: data)
        guard !decoded.stations.isEmpty else { throw URLError(.cannotParseResponse) }
        cachedStations = decoded.stations
        UserDefaults.standard.set(data, forKey: Self.stationsCacheKey)
        return decoded.stations
    }

    private func nearestStation(in stations: [Station], lat: Double, lon: Double) -> Station? {
        stations.min { a, b in
            GeoMath.haversineNm(lat1: lat, lon1: lon, lat2: a.lat, lon2: a.lng)
                < GeoMath.haversineNm(lat1: lat, lon1: lon, lat2: b.lat, lon2: b.lng)
        }
    }

    private func fetchPredictions(stationId: String) async throws -> [TidalCurrentPoint] {
        let nowDate = now()
        let calendar = Calendar(identifier: .gregorian)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: nowDate) ?? nowDate

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var components = URLComponents(string: Self.dataURL)!
        components.queryItems = [
            URLQueryItem(name: "station", value: stationId),
            URLQueryItem(name: "product", value: "currents_predictions"),
            URLQueryItem(name: "vel_type", value: "speed_dir"),
            URLQueryItem(name: "interval", value: "h"),
            URLQueryItem(name: "begin_date", value: dateFormatter.string(from: nowDate)),
            URLQueryItem(name: "end_date", value: dateFormatter.string(from: tomorrow)),
            URLQueryItem(name: "units", value: "english"),
            // GMT rather than the station's own local time - the response
            // timestamps are then unambiguous to parse (no "is this
            // standard or daylight time" question), and SwiftUI's date
            // formatting already renders the resulting Date in whatever
            // timezone the device is actually in.
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "application", value: "RPS"),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // JSONSerialization rather than Codable here: which top-level key
        // wraps the rows, and whether each field is a JSON string or
        // number, couldn't be confirmed against a live response (see the
        // file header) - so this tolerates the shapes that turned up
        // across NOAA's own docs and independent client implementations
        // rather than betting the whole feature on one guess.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let rows: [[String: Any]] = (object?["data"] as? [[String: Any]])
            ?? ((object?["current_predictions"] as? [String: Any])?["cp"] as? [[String: Any]])
            ?? []
        guard !rows.isEmpty else { throw URLError(.cannotParseResponse) }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        timeFormatter.timeZone = TimeZone(identifier: "UTC")

        let cutoff = nowDate.addingTimeInterval(-30 * 60)
        var points: [TidalCurrentPoint] = []
        for row in rows {
            guard
                let tString = (row["t"] as? String) ?? (row["Time"] as? String),
                let date = timeFormatter.date(from: tString),
                date >= cutoff,
                let speed = doubleValue(row["s"] ?? row["Speed"]),
                let direction = doubleValue(row["d"] ?? row["Direction"])
            else { continue }
            points.append(TidalCurrentPoint(date: date, towardDeg: direction, speedKts: speed))
        }
        return Array(points.prefix(24))
    }

    private func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let s = any as? String { return Double(s) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }
}
