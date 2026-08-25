//
//  RootView.swift
//  RPS
//
//  Switches between the launch spinner, sign-in, club selection, and the
//  main tabbed app based on `AppState.phase`.
//

import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.phase {
            case .launching:
                launchView
            case .signedOut:
                AuthGateView()
            case .needsClubSelection:
                ClubPickerView()
            case .ready:
                AppTabView()
            }
        }
        .task {
            if appState.phase == .launching {
                await appState.start()
            }
        }
    }

    private var launchView: some View {
        VStack(spacing: 20) {
            Image(systemName: "sailboat.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            ProgressView()
            // A silent spinner for 40 seconds reads as a broken app. Saying
            // what is actually happening costs nothing and buys patience.
            if appState.isWakingServer {
                VStack(spacing: 6) {
                    Text("Waking up the server…")
                        .font(.subheadline.weight(.medium))
                    Text("It sleeps when idle — this can take up to a minute the first time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .transition(.opacity)
                .padding(.horizontal, 40)
            }
        }
        .animation(.easeInOut, value: appState.isWakingServer)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
