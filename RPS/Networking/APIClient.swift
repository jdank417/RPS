//
//  APIClient.swift
//  RPS
//
//  Async/await URLSession client for the RPS backend. Handles JSON
//  encode/decode against the snake_case wire format, bearer auth, and
//  transparent 401 -> refresh -> retry-once, per the API contract.
//

import Foundation

/// Ensures only one refresh request is ever in flight at a time — several
/// concurrent calls hitting a 401 together (bootstrap firing off a handful
/// of requests, say) must all wait on the same refresh rather than racing
/// the backend with several refresh-token redemptions.
private actor TokenRefresher {
    private var inFlight: Task<TokenPair, Error>?

    func refresh(using client: APIClient) async throws -> TokenPair {
        if let inFlight { return try await inFlight.value }
        let task = Task<TokenPair, Error> {
            try await client.performRefresh()
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

/// Marker type for requests with no body (a plain GET), so the generic
/// `Body: Encodable` request builders have something concrete to infer.
private struct NoBody: Encodable {}

final class APIClient {

    static let shared = APIClient()

    private let settings: AppSettings
    private let keychain: KeychainStore
    private let session: URLSession
    private let refresher = TokenRefresher()
    private let cache = APICache.shared

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    init(settings: AppSettings = .shared, keychain: KeychainStore = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.keychain = keychain
        self.session = session
    }

    // MARK: - Auth

    func register(email: String, password: String, fullName: String?) async throws -> AuthResponse {
        try await send("/api/v1/auth/register", method: "POST", body: RegisterRequest(email: email, password: password, fullName: fullName), auth: false)
    }

    /// `/auth/login` is an OAuth2 password form, not JSON.
    func login(email: String, password: String) async throws -> AuthResponse {
        let form = "username=\(formEncode(email))&password=\(formEncode(password))"
        let url = try endpointURL("/api/v1/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.utf8)
        return try await execute(request, decodeAs: AuthResponse.self)
    }

    /// Performs the actual refresh call. Internal — callers should go through
    /// the `authorizedRequest` 401 path, not call this directly.
    fileprivate func performRefresh() async throws -> TokenPair {
        guard let refreshToken = keychain.refreshToken else { throw APIError.sessionExpired }
        do {
            let pair: TokenPair = try await send(
                "/api/v1/auth/refresh", method: "POST", body: RefreshRequest(refreshToken: refreshToken), auth: false
            )
            keychain.store(tokens: pair)
            return pair
        } catch {
            throw APIError.sessionExpired
        }
    }

    func logout() async {
        guard let refreshToken = keychain.refreshToken else { return }
        _ = try? await sendNoContent("/api/v1/auth/logout", method: "POST", body: LogoutRequest(refreshToken: refreshToken), auth: false)
        keychain.clear()
    }

    func changePassword(current: String, new: String) async throws {
        try await authorizedNoContent("/api/v1/auth/change-password", method: "POST", body: ChangePasswordRequest(currentPassword: current, newPassword: new))
    }

    // MARK: - User

    func me() async throws -> User {
        try await authorizedRequest("/api/v1/users/me", method: "GET", body: Optional<NoBody>.none)
    }

    func updateMe(_ update: UserUpdate) async throws -> User {
        try await authorizedRequest("/api/v1/users/me", method: "PATCH", body: update)
    }

    // MARK: - Bootstrap / clubs / mark lists / marks

    func bootstrap(clubSlug: String?) async throws -> Bootstrap {
        if let cached = cache.getBootstrap(clubSlug: clubSlug) {
            return cached
        }
        var path = "/api/v1/bootstrap"
        if let clubSlug, !clubSlug.isEmpty {
            path += "?club_slug=\(formEncode(clubSlug))"
        }
        let fresh: Bootstrap = try await authorizedRequest(path, method: "GET", body: Optional<NoBody>.none)
        cache.setBootstrap(fresh, clubSlug: clubSlug)
        return fresh
    }

    func clubs(region: String? = nil, country: String? = nil) async throws -> [YachtClub] {
        // Note: For simplicity, we only cache the unfiltered clubs() call.
        // Regional/country filtering happens rarely and usually at onboarding.
        guard region == nil && country == nil else {
            var query: [String] = []
            if let region, !region.isEmpty { query.append("region=\(formEncode(region))") }
            if let country, !country.isEmpty { query.append("country=\(formEncode(country))") }
            let path = "/api/v1/clubs" + (query.isEmpty ? "" : "?" + query.joined(separator: "&"))
            return try await authorizedRequest(path, method: "GET", body: Optional<NoBody>.none)
        }
        
        if let cached = cache.getClubs() {
            return cached
        }
        let path = "/api/v1/clubs"
        let fresh: [YachtClub] = try await authorizedRequest(path, method: "GET", body: Optional<NoBody>.none)
        cache.setClubs(fresh)
        return fresh
    }

    func club(slug: String) async throws -> YachtClub {
        try await authorizedRequest("/api/v1/clubs/\(formEncode(slug))", method: "GET", body: Optional<NoBody>.none)
    }

    func markLists(clubSlug: String) async throws -> [MarkList] {
        if let cached = cache.getMarkLists(clubSlug: clubSlug) {
            return cached
        }
        let path = "/api/v1/clubs/\(formEncode(clubSlug))/mark-lists"
        let fresh: [MarkList] = try await authorizedRequest(path, method: "GET", body: Optional<NoBody>.none)
        cache.setMarkLists(fresh, clubSlug: clubSlug)
        return fresh
    }

    func markList(id: UUID) async throws -> MarkList {
        try await authorizedRequest("/api/v1/mark-lists/\(id.uuidString)", method: "GET", body: Optional<NoBody>.none)
    }

    func marks(markListId: UUID) async throws -> [Mark] {
        if let cached = cache.getMarks(markListId: markListId) {
            return cached
        }
        let path = "/api/v1/mark-lists/\(markListId.uuidString)/marks"
        let fresh: [Mark] = try await authorizedRequest(path, method: "GET", body: Optional<NoBody>.none)
        cache.setMarks(fresh, markListId: markListId)
        return fresh
    }

    // MARK: - Core request plumbing

    private func endpointURL(_ path: String) throws -> URL {
        guard let base = settings.apiBaseURL else { throw APIError.notConfigured }
        guard let url = URL(string: path, relativeTo: base) else { throw APIError.notConfigured }
        return url
    }

    private func formEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? s
    }

    /// Builds and runs a request with an optional JSON body, no auth header.
    private func send<Body: Encodable, R: Decodable>(_ path: String, method: String, body: Body?, auth: Bool) async throws -> R {
        let request = try buildRequest(path: path, method: method, body: body, auth: auth)
        return try await execute(request, decodeAs: R.self)
    }

    private func sendNoContent<Body: Encodable>(_ path: String, method: String, body: Body?, auth: Bool) async throws {
        let request = try buildRequest(path: path, method: method, body: body, auth: auth)
        _ = try await executeNoContent(request)
    }

    /// Runs an authorized request; on a 401 it refreshes the token pair once
    /// and retries the original request, per the API contract. If refresh
    /// also fails, throws `.sessionExpired` so the caller can force sign-out.
    private func authorizedRequest<Body: Encodable, R: Decodable>(_ path: String, method: String, body: Body?) async throws -> R {
        let request = try buildRequest(path: path, method: method, body: body, auth: true)
        do {
            return try await execute(request, decodeAs: R.self)
        } catch APIError.server(status: 401, _) {
            _ = try await refresher.refresh(using: self)
            let retried = try buildRequest(path: path, method: method, body: body, auth: true)
            return try await execute(retried, decodeAs: R.self)
        }
    }

    private func authorizedNoContent<Body: Encodable>(_ path: String, method: String, body: Body?) async throws {
        let request = try buildRequest(path: path, method: method, body: body, auth: true)
        do {
            _ = try await executeNoContent(request)
        } catch APIError.server(status: 401, _) {
            _ = try await refresher.refresh(using: self)
            let retried = try buildRequest(path: path, method: method, body: body, auth: true)
            _ = try await executeNoContent(retried)
        }
    }

    private func buildRequest<Body: Encodable>(path: String, method: String, body: Body?, auth: Bool) throws -> URLRequest {
        let url = try endpointURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? encoder.encode(body)
        }
        if auth {
            guard let token = keychain.accessToken else { throw APIError.sessionExpired }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func execute<R: Decodable>(_ request: URLRequest, decodeAs: R.Type) async throws -> R {
        let data = try await run(request)
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Runs a request expecting a 204/empty body.
    @discardableResult
    private func executeNoContent(_ request: URLRequest) async throws -> Data {
        try await run(request)
    }

    /// Executes the request and returns the raw body data on success (2xx),
    /// throwing `.server` (with the FastAPI `detail`, when present) on
    /// failure and `.transport` on a network-layer error.
    private func run(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No response from server.")
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = try? decoder.decode(APIErrorBody.self, from: data).detail
            throw APIError.server(status: http.statusCode, detail: detail)
        }
        return data
    }
}

private extension CharacterSet {
    /// Safe for a URL query value: RFC 3986 unreserved plus a few of the
    /// commonly-allowed extras, excluding `&` and `=` which delimit pairs.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
