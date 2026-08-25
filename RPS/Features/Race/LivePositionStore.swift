//
//  LivePositionStore.swift
//  RPS
//
//  Continuous GPS via CLLocationManager (best-for-navigation accuracy),
//  ported from the reference app's `live-position.service.ts`. Publishes the
//  raw fix; the bearing/range/VMG *to* a target mark is derived in
//  `RaceViewModel`, which knows about the course — this store only knows
//  about the boat.
//

import Foundation
import CoreLocation
import Observation

struct LiveFix: Equatable {
    var lat: Double
    var lon: Double
    var accuracyM: Double?
    /// Course over ground in degrees true, when the device reports it. Only
    /// meaningful once actually moving; stationary GPS heading is noise.
    var headingDeg: Double?
    /// Speed over ground in knots, when reported.
    var speedKts: Double?
    var at: Date

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

private let movingKts = 0.5

@Observable
@MainActor
final class LivePositionStore: NSObject {

    var fix: LiveFix?
    var tracking = false
    var error: String?

    private let manager = CLLocationManager()

    var moving: Bool {
        guard let s = fix?.speedKts else { return false }
        return s >= movingKts
    }

    var coordinate: CLLocationCoordinate2D? { fix?.coordinate }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
    }

    func start() {
        guard !tracking else { return }
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            // Set intent flag so locationManagerDidChangeAuthorization will start updates
            tracking = true
            manager.requestWhenInUseAuthorization()
            return // Don't call startUpdatingLocation() until authorization is granted
        case .denied, .restricted:
            error = "Location is blocked — allow it in Settings to steer to the mark."
            return
        default:
            break
        }
        error = nil
        tracking = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        tracking = false
    }

    func toggle() {
        tracking ? stop() : start()
    }
}

extension LivePositionStore: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.fix = LiveFix(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                accuracyM: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil,
                headingDeg: location.course >= 0 ? location.course : nil,
                // CoreLocation reports m/s; sailors read knots.
                speedKts: location.speed >= 0 ? location.speed * 1.943844 : nil,
                at: location.timestamp
            )
            self.error = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.error = "Lost GPS (\(error.localizedDescription))."
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.tracking {
                    manager.startUpdatingLocation()
                } else if !self.tracking, self.error == nil {
                    // Authorization just granted after a pending start() —
                    // nothing to do until the sailor taps track again, to
                    // avoid surprising them with GPS running unasked.
                }
            case .denied, .restricted:
                self.error = "Location is blocked — allow it in Settings to steer to the mark."
                self.tracking = false
            default:
                break
            }
        }
    }
}
