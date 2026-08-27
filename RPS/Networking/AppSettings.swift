//
//  AppSettings.swift
//  RPS
//
//  User-editable, locally-persisted app settings — chiefly the API base URL,
//  since the backend's real deployed address isn't known at build time. Kept
//  separate from Keychain: this is configuration, not a secret.
//

import Foundation
import Observation

@Observable
final class AppSettings {

    static let shared = AppSettings()

    private enum Keys {
        static let apiBaseURL = "rps.settings.apiBaseURL"
        static let variationDeg = "rps.settings.variationDeg"
        static let useMagnetic = "rps.settings.useMagnetic"
    }

    private let defaults: UserDefaults

    /// The API's base URL, hardcoded to the production backend.
    var apiBaseURLString: String {
        didSet { defaults.set(apiBaseURLString, forKey: Keys.apiBaseURL) }
    }

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

    var isConfigured: Bool {
        apiBaseURL != nil
    }

    var apiBaseURL: URL? {
        let trimmed = apiBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            return nil
        }
        return url
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiBaseURLString = defaults.string(forKey: Keys.apiBaseURL) ?? "https://rps-admin-backend.onrender.com"
        self.variationDeg = defaults.object(forKey: Keys.variationDeg) as? Double ?? -14.6
        self.useMagnetic = defaults.object(forKey: Keys.useMagnetic) as? Bool ?? false
    }
}
