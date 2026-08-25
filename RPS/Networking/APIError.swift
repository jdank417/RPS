//
//  APIError.swift
//  RPS
//

import Foundation

enum APIError: Error, LocalizedError, Equatable {
    /// The API base URL hasn't been set (or isn't valid) in Settings yet.
    case notConfigured
    case transport(String)
    case decoding(String)
    /// A 4xx/5xx response. `detail` is FastAPI's `{"detail": "..."}` body,
    /// surfaced to the user directly when present.
    case server(status: Int, detail: String?)
    /// Refreshing the session failed (or there was nothing to refresh) after
    /// a 401 — the caller should force a sign-out.
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Set the server address in Settings before signing in."
        case .transport(let message):
            return message
        case .decoding:
            return "The server sent a response this app didn't understand."
        case .server(_, let detail):
            return detail ?? "Something went wrong talking to the server."
        case .sessionExpired:
            return "Your session expired — please sign in again."
        }
    }
}
