//
//  AppSettings.swift
//  RPS
//
//  User-editable, locally-persisted app settings. Kept separate from
//  Keychain: this is configuration, not a secret.
//

import Foundation
import Observation

@Observable
final class AppSettings {

    static let shared = AppSettings()

    private enum Keys {
        static let variationDeg = "rps.settings.variationDeg"
        static let useMagnetic = "rps.settings.useMagnetic"
    }

    private let defaults: UserDefaults

    /// The RPS backend's address. Fixed, not user-editable: every club runs
    /// on the same shared platform, so there's nothing to point this at
    /// instead — the one time this *was* an editable setting, a mistyped
    /// URL was a support dead end with no screen left to fix it from.
    let apiBaseURLString = "https://rps-admin-backend.onrender.com"

    /// Magnetic variation in degrees, applied to true headings throughout the
    /// app. Positive is east, negative is west, matching the reference app's
    /// convention (e.g. -14.6 for a westerly variation of 14.6°).
    var variationDeg: Double {
        didSet { defaults.set(variationDeg, forKey: Keys.variationDeg) }
    }

    /// Whether headings lead with magnetic rather than true.
    ///
    /// Defaults to false - true-first. The course is computed in degrees
    /// true, the forecast reports wind in degrees true, and the start-line
    /// bias is worked out in degrees true, so true is the number that agrees
    /// with everything else on screen. Sailors steering to a bulkhead
    /// compass want magnetic, hence the switch; the other one is always
    /// shown underneath either way.
    var useMagnetic: Bool {
        didSet { defaults.set(useMagnetic, forKey: Keys.useMagnetic) }
    }

    var apiBaseURL: URL? { URL(string: apiBaseURLString) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.variationDeg = defaults.object(forKey: Keys.variationDeg) as? Double ?? -14.6
        self.useMagnetic = defaults.object(forKey: Keys.useMagnetic) as? Bool ?? false
    }
}
