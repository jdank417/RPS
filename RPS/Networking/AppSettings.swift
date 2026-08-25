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

    /// The API's base URL, e.g. "https://api.example.com". Empty until the
    /// sailor (or the person setting up their boat's phone) fills it in —
    /// there is no hardcoded guess, since the backend's deployed address
    /// isn't known at build time.
    var apiBaseURLString: String {
        didSet { defaults.set(apiBaseURLString, forKey: Keys.apiBaseURL) }
    }

    /// Magnetic variation in degrees, applied to true headings throughout the
    /// app. Positive is east, negative is west, matching the reference app's
    /// convention (e.g. -14.6 for a westerly variation of 14.6°).
    var variationDeg: Double {
        didSet { defaults.set(variationDeg, forKey: Keys.variationDeg) }
    }

    /// Whether headings are displayed magnetic-first (still shows true
    /// alongside it).
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
        self.apiBaseURLString = defaults.string(forKey: Keys.apiBaseURL) ?? ""
        self.variationDeg = defaults.object(forKey: Keys.variationDeg) as? Double ?? -14.6
        self.useMagnetic = defaults.object(forKey: Keys.useMagnetic) as? Bool ?? false
    }
}
