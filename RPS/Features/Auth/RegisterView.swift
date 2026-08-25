//
//  RegisterView.swift
//  RPS
//

import SwiftUI

struct RegisterView: View {
    @Environment(AppState.self) private var appState

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                TextField("Full name (optional)", text: $fullName)
                    .textContentType(.name)

                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)

                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
            }
            .textFieldStyle(.roundedBorder)

            if let mismatchMessage {
                Text(mismatchMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await register() }
            } label: {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Create Account").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit || isLoading)
        }
    }

    private var mismatchMessage: String? {
        guard !confirmPassword.isEmpty, confirmPassword != password else { return nil }
        return "Passwords don't match yet."
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 8
            && password == confirmPassword
    }

    private func register() async {
        guard canSubmit else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let trimmedName = fullName.trimmingCharacters(in: .whitespaces)
        do {
            try await appState.register(
                email: email.trimmingCharacters(in: .whitespaces),
                password: password,
                fullName: trimmedName.isEmpty ? nil : trimmedName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RegisterView()
        .environment(AppState())
        .padding()
}
