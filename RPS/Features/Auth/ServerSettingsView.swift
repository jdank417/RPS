//
//  ServerSettingsView.swift
//  RPS
//
//  Lets the sailor (or whoever set up the boat's phone) point the app at the
//  backend's deployed address. The URL isn't known at build time, so it's a
//  plain editable, persisted setting rather than a hardcoded guess.
//

import SwiftUI

struct ServerSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://api.example.com", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.body.monospaced())
                } header: {
                    Text("API base URL")
                } footer: {
                    Text("The address of the RPS backend. Ask your club admin if you don't have this.")
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        settings.apiBaseURLString = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { draft = settings.apiBaseURLString }
        }
    }
}

#Preview {
    ServerSettingsView()
        .environment(AppSettings.shared)
}
