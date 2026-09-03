//
//  Binding+Limits.swift
//  RPS
//

import SwiftUI

extension Binding where Value == String {
    /// Truncates on every write so a text field can never hold more than
    /// `limit` characters - the client-side twin of rps_admin's own
    /// `Field(max_length:)` caps on these same values, so a long paste is
    /// clamped locally instead of round-tripping to the server for a 422.
    ///
    /// Wrap the binding at the call site: `TextField("Name", text: $name.capped(at: 255))`.
    func capped(at limit: Int) -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { newValue in wrappedValue = String(newValue.prefix(limit)) }
        )
    }
}

/// Field-length limits mirrored from rps_admin's Pydantic schemas
/// (`app/schemas/common.py`'s `Name255`/`BcryptPassword`, and
/// `RegisterRequest.email`'s explicit cap) so both clients enforce the same
/// bounds the API does.
enum InputLimit {
    static let name = 255
    static let email = 320
    /// bcrypt only ever looks at a password's first 72 bytes.
    static let password = 72
}
