//
//  RaceWeatherService.swift
//  RPS
//
//  A fuller picture than the mid-race wind reading used in `WindService`:
//  current conditions plus a several-hour wind trend, pressure and its
//  trend, visibility and UV, straight from WeatherKit. This exists to show
//  what WeatherKit adds beyond the plain forecast wind used elsewhere - so
//  unlike `WindService`, there is deliberately no Open-Meteo fallback here.
//  Until the WeatherKit capability is enabled for this app's Bundle ID
//  (Xcode -> Signing & Capabilities, which itself needs an active paid
//  Apple Developer Program membership), this reports itself unavailable
//  rather than quietly substituting a different provider that couldn't
//  show the same picture anyway.
//

import Foundation
import Observation
import CoreLocation
import WeatherKit

/// WeatherKit's own three-way pressure trend, re-expressed as a plain
/// value so the view layer doesn't need to import WeatherKit itself.
enum PressureTrendReading: Equatable {
    case rising, falling, steady

    init(_ trend: PressureTrend) {
        switch trend {
        case .rising: self = .rising
        case .falling: self = .falling
        case .steady: self = .steady
        @unknown default: self = .steady
        }
    }

    var label: String {
        switch self {
        case .rising: return "Rising"
        case .falling: return "Falling"
        case .steady: return "Steady"
        }
    }

    /// A rising glass ahead of a race usually means more breeze is coming;
    /// a falling one is the classic warning of a front or a squall behind
    /// it - worth a glance before the gun goes.
    var symbolName: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .steady: return "arrow.right"
        }
    }
}

/// One hour's forecast wind - the thing this tab exists to show: is the
/// breeze building or dying over the race, and which way is it shifting.
struct HourlyWindPoint: Identifiable, Equatable {
    var date: Date
    var symbolName: String
    var windFromDeg: Double
    var windSpeed: Measurement<UnitSpeed>
    var precipitationChance: Double

    var id: Date { date }
}

struct RaceWeatherSnapshot: Equatable {
    var observedAt: Date
    var symbolName: String
    var temperature: Measurement<UnitTemperature>
    var windSpeed: Measurement<UnitSpeed>
    var windFromDeg: Double
    var gust: Measurement<UnitSpeed>?
    var pressure: Measurement<UnitPressure>
    var pressureTrend: PressureTrendReading
    /// 0...1.
    var humidity: Double
    var visibility: Measurement<UnitLength>
    var uvIndex: Int
    /// The next several hours, for the trend - not a full multi-day
    /// forecast, which isn't what a race committee or a crew needs from
    /// this screen.
    var hourly: [HourlyWindPoint]
}

@Observable
@MainActor
final class RaceWeatherService {

    private let weatherKit: WeatherService
    private let now: () -> Date

    var snapshot: RaceWeatherSnapshot?
    var isLoading = false
    /// Set on any failure - most commonly because the WeatherKit capability
    /// isn't enabled for this app yet. There's no second provider to fall
    /// back to here, so unlike `WindService` this is surfaced rather than
    /// silently swallowed: the whole point of this tab is what WeatherKit
    /// specifically adds.
    var error: String?

    private var lastFetchAt: Date?
    private var lastLat: Double?
    private var lastLon: Double?

    init(weatherKit: WeatherService = .shared, now: @escaping () -> Date = Date.init) {
        self.weatherKit = weatherKit
        self.now = now
    }

    var stale: Bool {
        guard let observedAt = snapshot?.observedAt else { return false }
        return now().timeIntervalSince(observedAt) > 30 * 60
    }

    /// Worth a fresh fetch: never fetched yet, moved far enough that the
    /// forecast cell has probably changed, or the last one is getting old.
    /// Cheap enough to call from `.onAppear` and a pull-to-refresh alike.
    func shouldRefresh(lat: Double, lon: Double) -> Bool {
        guard let lastFetchAt else { return true }
        if let lastLat, let lastLon,
           GeoMath.haversineNm(lat1: lastLat, lon1: lastLon, lat2: lat, lon2: lon) > 3 {
            return true
        }
        return now().timeIntervalSince(lastFetchAt) > 15 * 60
    }

    func refresh(lat: Double, lon: Double, force: Bool = false) async {
        guard force || shouldRefresh(lat: lat, lon: lon) else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let location = CLLocation(latitude: lat, longitude: lon)
            let (current, hourly) = try await weatherKit.weather(for: location, including: .current, .hourly)

            let hourlyPoints: [HourlyWindPoint] = hourly.prefix(9).map { hour in
                HourlyWindPoint(
                    date: hour.date,
                    symbolName: hour.symbolName,
                    windFromDeg: hour.wind.direction.converted(to: .degrees).value,
                    windSpeed: hour.wind.speed.converted(to: .knots),
                    precipitationChance: hour.precipitationChance
                )
            }

            snapshot = RaceWeatherSnapshot(
                observedAt: current.metadata.date,
                symbolName: current.symbolName,
                temperature: current.temperature,
                windSpeed: current.wind.speed.converted(to: .knots),
                windFromDeg: current.wind.direction.converted(to: .degrees).value,
                gust: current.wind.gust?.converted(to: .knots),
                pressure: current.pressure,
                pressureTrend: PressureTrendReading(current.pressureTrend),
                humidity: current.humidity,
                visibility: current.visibility,
                uvIndex: current.uvIndex.value,
                hourly: hourlyPoints
            )
            error = nil
            lastFetchAt = now()
            lastLat = lat
            lastLon = lon
        } catch {
            // Deliberately not assuming *why* - could be the capability
            // still isn't enabled, or a genuine transient failure once it
            // is. Either way there's nothing else to fall back to here.
            self.error = "Couldn't load WeatherKit data (\(error.localizedDescription)). If you haven't already, enable the WeatherKit capability for RPS in Xcode (Signing & Capabilities) - needs an active Apple Developer Program membership."
            lastFetchAt = now()
        }
    }
}
