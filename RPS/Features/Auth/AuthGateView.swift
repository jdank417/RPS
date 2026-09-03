//
//  AuthGateView.swift
//  RPS
//
//  The signed-out root: brand header and login/register switcher. Shown
//  whenever `AppState.phase == .signedOut`.
//

import SwiftUI

struct AuthGateView: View {
    private enum Mode: String, CaseIterable {
        case login = "Sign In"
        case register = "Create Account"
    }

    @State private var mode: Mode = .login

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Group {
                        switch mode {
                        case .login: LoginView()
                        case .register: RegisterView()
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sailboat.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("RPS")
                .font(.largeTitle.bold())
            Text("Regatta Positioning System")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AuthGateView()
        .environment(AppState())
        .environment(AppSettings.shared)
}
