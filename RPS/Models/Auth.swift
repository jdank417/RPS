//
//  Auth.swift
//  RPS
//

import Foundation

struct TokenPair: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

/// Login/register response: the token pair plus the signed-in user, so the
/// client doesn't need a follow-up GET /users/me to know who it is.
struct AuthResponse: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var tokenType: String
    var user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case user
    }
}

struct RegisterRequest: Encodable {
    var email: String
    var password: String
    var fullName: String?

    enum CodingKeys: String, CodingKey {
        case email, password
        case fullName = "full_name"
    }
}

struct RefreshRequest: Encodable {
    var refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

struct LogoutRequest: Encodable {
    var refreshToken: String
    enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
}

struct ChangePasswordRequest: Encodable {
    var currentPassword: String
    var newPassword: String
    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
        case newPassword = "new_password"
    }
}

/// FastAPI's default error body shape.
struct APIErrorBody: Decodable {
    var detail: String?
}
