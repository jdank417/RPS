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

/// Where a tap on a Home Screen widget should land - set from
/// `RPSApp`'s `.onOpenURL`, consumed (and cleared) by `AppTabView`, which
/// owns the tab/segment selection this needs to reach.
enum RPSDeepLink: Equatable {
    /// The "Start Race" tap on RPSRaceWidget, when no race is running.
    case countdown
    /// A tap on RPSRaceWidget while it's mirroring an in-progress leg.
    case leg
}

@Observable
@MainActor
final class AppState {

    private(set) var phase: SessionPhase = .launching
    private(set) var bootstrap: Bootstrap?
    var errorMessage: String?

    /// True while a refresh is running behind an already-visible screen, so
    /// the UI can show a quiet indicator instead of blocking.
    private(set) var isRevalidating = false
    /// Set when a request has been outstanding long enough that it is almost
    /// certainly the backend cold-starting, so the launch screen can say so
    /// rather than looking hung.
    private(set) var isWakingServer = false

    /// Set once by `.onOpenURL`, read once by `AppTabView` (which clears
    /// it back to nil after acting on it, so re-showing the same tab
    /// doesn't re-fire the navigation on every subsequent view update).
    var pendingDeepLink: RPSDeepLink?

    private let api: APIClient
    private let keychain: KeychainStore
    private let cache: APICache

    init(api: APIClient = .shared, keychain: KeychainStore = .shared, cache: APICache = .shared) {
        self.api = api
        self.keychain = keychain
        self.cache = cache
    }

    var currentUser: User? { bootstrap?.user }

    /// True once a signed-in user's own record has loaded and shows no
    /// waiver acceptance on file - a brand-new registration already sends
    /// acceptance with the account, so this only ever fires for one that
    /// predates the waiver, or an older version of it. `RootView` shows a
    /// mandatory gate ahead of club selection and the tab bar while this
    /// is true.
    var needsWaiverAcceptance: Bool {
        guard let currentUser else { return false }
        return currentUser.liabilityWaiverAcceptedAt == nil
    }

    // MARK: - Deep links

    /// `rps://countdown` or `rps://leg`, from RPSRaceWidget's tap targets -
    /// registered as this app's custom URL scheme under the RPS target's
    /// Info tab in Xcode (Info -> URL Types), not Signing & Capabilities.
    func handle(url: URL) {
        switch url.host {
        case "countdown": pendingDeepLink = .countdown
        case "leg": pendingDeepLink = .leg
        default: break
        }
    }

    // MARK: - Launch

    /// Called once when the root view appears: silently validates whatever
    /// session is in the Keychain, rather than always dropping the sailor
    /// back on the login screen.
    ///
    /// Stale-while-revalidate. If a previous session left a bootstrap
    /// cached, the app opens straight into it and refreshes behind the
    /// scenes; only a genuinely first-ever launch waits on the network.
    /// That matters here because the backend sleeps when idle, so the honest
    /// choice was between an instant slightly-stale course list and staring
    /// at a spinner for the better part of a minute.
    func start() async {
        guard keychain.hasSession else {
            phase = .signedOut
            return
        }

        if let cached = cache.getStaleBootstrap() {
            bootstrap = cached
            phase = (cached.club == nil && cached.clubs.count > 1) ? .needsClubSelection : .ready
            await loadBootstrap(clubSlug: cached.club?.slug, revalidating: true)
        } else {
            await loadBootstrap()
        }
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        let response = try await api.login(email: email, password: password)
        // Whoever just signed in may not be whoever this phone cached last.
        cache.clearAll()
        keychain.store(tokens: TokenPair(accessToken: response.accessToken, refreshToken: response.refreshToken, tokenType: response.tokenType))
        await loadBootstrap()
    }

    func register(email: String, password: String, fullName: String?) async throws {
        let response = try await api.register(email: email, password: password, fullName: fullName)
        cache.clearAll()
        keychain.store(tokens: TokenPair(accessToken: response.accessToken, refreshToken: response.refreshToken, tokenType: response.tokenType))
        await loadBootstrap()
    }

    /// Permanently deletes this account, then tears the session down.
    ///
    /// Required by App Store Review guideline 5.1.1(v). Note this does NOT
    /// call `api.logout()` the way `signOut` does: the account is gone
    /// server-side, so redeeming its refresh token would 401 against a user
    /// that no longer exists. The local teardown is the same otherwise -
    /// leaving this account's cached clubs and mark lists behind would show
    /// them to whoever signs in on this phone next.
    func deleteAccount(password: String) async throws {
        try await api.deleteMe(password: password)
        cache.clearAll()
        keychain.clear()
        bootstrap = nil
        errorMessage = nil
        phase = .signedOut
    }

    func signOut() async {
        await api.logout()
        // Everything cached is this account's data - clubs, mark lists, the
        // bootstrap payload with their name and home club in it. Leaving it
        // behind would show the next person to sign in on this phone the
        // previous account's data.
        cache.clearAll()
        keychain.clear()
        bootstrap = nil
        errorMessage = nil
        phase = .signedOut
    }

    // MARK: - Bootstrap / club selection

    /// Fetches (or re-fetches) the bootstrap payload and settles `phase`
    /// based on whether a home club is resolved.
    ///
    /// `revalidating` means a cached payload is already on screen: failures
    /// then stay quiet rather than tearing down a working session, because
    /// being briefly offline on the water is normal, not exceptional.
    func loadBootstrap(clubSlug: String? = nil, revalidating: Bool = false) async {
        if revalidating { isRevalidating = true }
        let waking = startWakingServerWatchdog(active: !revalidating)
        defer {
            waking?.cancel()
            isWakingServer = false
            isRevalidating = false
        }

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
            // The refresh token is genuinely dead - this one does end the
            // session, cached payload or not, and the cache goes with it so
            // the next account to sign in doesn't inherit this one's data.
            cache.clearAll()
            keychain.clear()
            bootstrap = nil
            phase = .signedOut
        } catch {
            // A network failure while revalidating is not a reason to throw
            // away a session the sailor is actively using.
            guard !revalidating else { return }
            errorMessage = error.localizedDescription
            if bootstrap == nil { phase = .signedOut }
        }
    }

    /// Flips `isWakingServer` once a request has been outstanding long
    /// enough that it is almost certainly a sleeping backend waking up.
    private func startWakingServerWatchdog(active: Bool) -> Task<Void, Never>? {
        guard active else { return nil }
        return Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.isWakingServer = true
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

    /// Pull-to-refresh: drops cached reference data so marks edited in the
    /// club admin console show up, then reloads.
    func hardRefresh() async {
        cache.clearAll()
        await loadBootstrap(clubSlug: bootstrap?.club?.slug)
    }

    func updateProfile(fullName: String?) async throws {
        let updated = try await api.updateMe(UserUpdate(fullName: fullName))
        bootstrap?.user = updated
    }

    func changePassword(current: String, new: String) async throws {
        try await api.changePassword(current: current, new: new)
    }

    func acceptWaiver() async throws {
        let updated = try await api.acceptWaiver()
        bootstrap?.user = updated
    }

    func requestClubAdmin(clubSlug: String, message: String?) async throws -> ClubAdminRequest {
        try await api.requestClubAdmin(clubSlug: clubSlug, message: message)
    }

    func myClubAdminRequests() async throws -> [ClubAdminRequest] {
        try await api.myClubAdminRequests()
    }

    /// Replaces the loaded mark lists' selection with a specific list,
    /// fetching its marks. Used when the sailor picks a different mark list
    /// than the backend's default.
    func selectMarkList(_ list: MarkList, forceRefresh: Bool = false) async throws -> [Mark] {
        try await api.marks(markListId: list.id, forceRefresh: forceRefresh)
    }
}
