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
        VStack(spacing: 16) {
            Image(systemName: "sailboat.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
