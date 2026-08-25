//
//  AppState.swift
//  RPS
//
//  Top-level app orchestration: session lifecycle (launch -> silently
//  validate/refresh -> signed in/out), club selection, and holding the
//  bootstrap payload the rest of the app reads from. This is the one
//  @Observable object the whole view tree shares via the environment.
//

import Foundation
import Observation

/// Where the app is in its startup/session lifecycle.
enum SessionPhase: Equatable {
    /// Checking the Keychain / validating a stored session.
    case launching
    case signedOut
    /// Signed in, but the sailor has no home club and there's more than one
    /// to choose from — `bootstrap.clubs` has the list to pick from.
    case needsClubSelection
    case ready
}

@Observable
@MainActor
final class AppState {

    private(set) var phase: SessionPhase = .launching
    private(set) var bootstrap: Bootstrap?
    var errorMessage: String?

    private let api: APIClient
    private let keychain: KeychainStore

    init(api: APIClient = .shared, keychain: KeychainStore = .shared) {
        self.api = api
        self.keychain = keychain
    }

    var currentUser: User? { bootstrap?.user }

    // MARK: - Launch

    /// Called once when the root view appears: silently validates whatever
    /// session is in the Keychain, rather than always dropping the sailor
    /// back on the login screen.
    func start() async {
        guard keychain.hasSession else {
            phase = .signedOut
            return
        }
        await loadBootstrap()
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        let response = try await api.login(email: email, password: password)
        keychain.store(tokens: TokenPair(accessToken: response.accessToken, refreshToken: response.refreshToken, tokenType: response.tokenType))
        await loadBootstrap()
    }

    func register(email: String, password: String, fullName: String?) async throws {
        let response = try await api.register(email: email, password: password, fullName: fullName)
        keychain.store(tokens: TokenPair(accessToken: response.accessToken, refreshToken: response.refreshToken, tokenType: response.tokenType))
        await loadBootstrap()
    }

    func signOut() async {
        await api.logout()
        keychain.clear()
        bootstrap = nil
        errorMessage = nil
        phase = .signedOut
    }

    // MARK: - Bootstrap / club selection

    /// Fetches (or re-fetches) the bootstrap payload and settles `phase`
    /// based on whether a home club is resolved.
    func loadBootstrap(clubSlug: String? = nil) async {
        do {
            let payload = try await api.bootstrap(clubSlug: clubSlug)
            bootstrap = payload
            errorMessage = nil
            if payload.club == nil && payload.clubs.count > 1 {
                phase = .needsClubSelection
            } else {
                phase = .ready
            }
        } catch APIError.sessionExpired {
            keychain.clear()
            bootstrap = nil
            phase = .signedOut
        } catch {
            errorMessage = error.localizedDescription
            // A launch-time bootstrap failure (offline, server hiccup)
            // shouldn't strand the sailor on a blank screen if we already
            // know who they are from a previous session — but with nothing
            // cached yet, signed-out is the honest state to show.
            if bootstrap == nil { phase = .signedOut }
        }
    }

    /// Sets the sailor's home club, then re-bootstraps against it — the flow
    /// the club picker drives.
    func selectHomeClub(_ club: YachtClub) async throws {
        _ = try await api.updateMe(UserUpdate(homeClubId: club.id))
        await loadBootstrap(clubSlug: club.slug)
    }

    /// Refreshes the current bootstrap (e.g. after the sailor switches mark
    /// lists or the profile screen edits their name).
    func refresh() async {
        await loadBootstrap(clubSlug: bootstrap?.club?.slug)
    }

    func updateProfile(fullName: String?) async throws {
        let updated = try await api.updateMe(UserUpdate(fullName: fullName))
        bootstrap?.user = updated
    }

    func changePassword(current: String, new: String) async throws {
        try await api.changePassword(current: current, new: new)
    }

    /// Replaces the loaded mark lists' selection with a specific list,
    /// fetching its marks. Used when the sailor picks a different mark list
    /// than the backend's default.
    func selectMarkList(_ list: MarkList) async throws -> [Mark] {
        try await api.marks(markListId: list.id)
    }
}
