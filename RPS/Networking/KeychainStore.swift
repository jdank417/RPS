//
//  KeychainStore.swift
//  RPS
//
//  Stores the access/refresh token pair in the Keychain — never UserDefaults,
//  since these are bearer credentials with real value if leaked. Deliberately
//  tiny: just get/set/delete for the handful of strings this app needs to
//  persist securely.
//

import Foundation
import Security

/// A minimal, synchronous wrapper over the Keychain Services API for storing
/// small secrets (tokens). Safe to call from any thread; each call is a
/// self-contained Keychain transaction.
final class KeychainStore: Sendable {

    static let shared = KeychainStore()

    private let service = "com.rps.auth"

    private enum Key: String {
        case accessToken = "accessToken"
        case refreshToken = "refreshToken"
    }

    // MARK: - Token pair convenience

    var accessToken: String? {
        get { read(.accessToken) }
        set {
            if let newValue { write(newValue, for: .accessToken) } else { delete(.accessToken) }
        }
    }

    var refreshToken: String? {
        get { read(.refreshToken) }
        set {
            if let newValue { write(newValue, for: .refreshToken) } else { delete(.refreshToken) }
        }
    }

    func store(tokens: TokenPair) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
    }

    func clear() {
        delete(.accessToken)
        delete(.refreshToken)
    }

    var hasSession: Bool { refreshToken != nil }

    // MARK: - Raw Keychain operations

    private func read(_ key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let attributes: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    private func delete(_ key: Key) {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}
