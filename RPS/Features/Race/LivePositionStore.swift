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
import UIKit

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

    /// Mirrored into observable state because `CLLocationManager`'s own
    /// property isn't observable - a view reading it directly would never
    /// re-render when the sailor grants or revokes permission.
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Counts fixes received this session. Zero while authorised and
    /// tracking is the specific symptom of "permission fine, no signal".
    private(set) var fixCount = 0

    private let manager = CLLocationManager()

    var moving: Bool {
        guard let s = fix?.speedKts else { return false }
        return s >= movingKts
    }

    var coordinate: CLLocationCoordinate2D? { fix?.coordinate }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// Plain-English account of what the receiver is actually doing, so a
    /// sailor (or whoever they report it to) can tell "permission refused"
    /// apart from "waiting for a fix" apart from "never asked" - three very
    /// different problems that otherwise all look like "GPS doesn't work".
    var statusDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "Permission not requested yet"
        case .denied: return "Permission denied — enable Location in Settings"
        case .restricted: return "Location restricted on this device"
        case .authorizedWhenInUse, .authorizedAlways:
            if !tracking { return "Allowed — GPS off" }
            return fixCount == 0 ? "Allowed — waiting for first fix…" : "Allowed — tracking"
        @unknown default: return "Unknown authorization state"
        }
    }

    /// Set when the sailor taps "Stop GPS", so returning to the Race tab
    /// doesn't quietly switch it back on behind them.
    private var stoppedDeliberately = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        authorizationStatus = manager.authorizationStatus
        // CoreLocation pauses updates on its own when it decides you have
        // stopped moving. On a boat sitting head-to-wind before a start, or
        // parked in a lull, that is exactly when the sailor still needs a
        // position - so opt out rather than lose the fix at the worst moment.
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Begins tracking, honouring an earlier deliberate stop unless this is
    /// an explicit request (`userInitiated`).
    func start(userInitiated: Bool = true) {
        if !userInitiated && stoppedDeliberately { return }
        if userInitiated { stoppedDeliberately = false }
        guard !tracking else { return }

        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            // Record the intent, then wait: calling startUpdatingLocation()
            // before the authorization callback lands is unreliable, and
            // requestWhenInUseAuthorization() returns immediately rather
            // than when the sailor actually taps Allow.
            tracking = true
            manager.requestWhenInUseAuthorization()
            return
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
        stoppedDeliberately = true
        manager.stopUpdatingLocation()
        tracking = false
    }

    /// Opens this app's page in Settings, the only place a denied location
    /// permission can be granted again.
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
            self.fixCount += 1
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
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                // `tracking` was set by start() before it returned to wait on
                // this callback; that flag is the record that the sailor
                // asked for GPS. Without it, authorization granted for some
                // other reason should not start the receiver unasked.
                if self.tracking {
                    self.error = nil
                    manager.startUpdatingLocation()
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
