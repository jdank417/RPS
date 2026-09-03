//
//  WaiverGateView.swift
//  RPS
//
//  Shown by RootView in place of club selection / the tab bar whenever
//  AppState.needsWaiverAcceptance is true - only ever an account that
//  predates the waiver, or an older version of it, since registration
//  already requires accepting it. See RPS/Support/Waiver.swift.
//

import SwiftUI

struct WaiverGateView: View {
    @Environment(AppState.self) private var appState

    @State private var accepted = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Waiver.intro)
                    Text(Waiver.leadIn)
                    ForEach(Waiver.clauses) { clause in
                        (Text(clause.title).fontWeight(.bold) + Text(" \(clause.body)"))
                    }
                    Text(Waiver.closing)
                        .fontWeight(.semibold)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
            }
            .navigationTitle("Before You Continue")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Toggle(isOn: $accepted) {
                        Text("I have read and agree to the Assumption of Risk & Disclaimer above.")
                            .font(.footnote)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Button("Sign Out") {
                            Task { await appState.signOut() }
                        }
                        .disabled(isLoading)

                        Spacer()

                        Button {
                            Task { await accept() }
                        } label: {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Accept & Continue")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!accepted || isLoading)
                    }
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private func accept() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await appState.acceptWaiver()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    WaiverGateView()
        .environment(AppState())
}
