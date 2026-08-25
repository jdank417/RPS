//
//  AuthGateView.swift
//  RPS
//
//  The signed-out root: brand header, login/register switcher, and access to
//  server settings. Shown whenever `AppState.phase == .signedOut`.
//

import SwiftUI

struct AuthGateView: View {
    private enum Mode: String, CaseIterable {
        case login = "Sign In"
        case register = "Create Account"
    }

    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @State private var mode: Mode = .login
    @State private var showServerSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    if !settings.isConfigured {
                        serverWarning
                    }

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showServerSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Server settings")
                }
            }
            .sheet(isPresented: $showServerSettings) {
                ServerSettingsView()
            }
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

    private var serverWarning: some View {
        Label("Set the server address in Settings before signing in.", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }
}

#Preview {
    AuthGateView()
        .environment(AppState())
        .environment(AppSettings.shared)
}
