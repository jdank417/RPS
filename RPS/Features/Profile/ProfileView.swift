//
//  ProfileView.swift
//  RPS
//
//  Edit full name, change home club, change password, server settings, and
//  sign out.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @State private var fullName = ""
    @State private var isSavingName = false
    @State private var nameSaved = false

    @State private var showClubPicker = false
    @State private var showChangePassword = false
    @State private var showServerSettings = false
    @State private var showInfo = false
    @State private var showSignOutConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Email", value: appState.currentUser?.email ?? "—")

                    HStack {
                        TextField("Full name", text: $fullName)
                            .textContentType(.name)
                            .onSubmit { Task { await saveName() } }
                        if isSavingName {
                            ProgressView()
                        } else if nameSaved {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }

                Section("Club") {
                    Button {
                        showClubPicker = true
                    } label: {
                        LabeledContent("Home club", value: appState.bootstrap?.club?.name ?? "Not set")
                    }
                    .foregroundStyle(.primary)
                }

                Section("Security") {
                    Button("Change Password") { showChangePassword = true }
                }

                Section("App") {
                    Button("Server Settings") { showServerSettings = true }
                    Button("Map Key & Disclaimer") { showInfo = true }
                    LabeledContent("Magnetic variation", value: String(format: "%.1f°", settings.variationDeg))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Text("Sign Out").frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Profile")
            .onAppear { fullName = appState.currentUser?.fullName ?? "" }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await appState.signOut() } }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showClubPicker) {
                ClubPickerView()
            }
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordView()
            }
            .sheet(isPresented: $showServerSettings) {
                ServerSettingsView()
            }
            .sheet(isPresented: $showInfo) {
                DisclaimerView()
            }
        }
    }

    private func saveName() async {
        let trimmed = fullName.trimmingCharacters(in: .whitespaces)
        guard trimmed != (appState.currentUser?.fullName ?? "") else { return }
        isSavingName = true
        errorMessage = nil
        nameSaved = false
        defer { isSavingName = false }
        do {
            try await appState.updateProfile(fullName: trimmed.isEmpty ? nil : trimmed)
            nameSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ChangePasswordView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current password", text: $current)
                    SecureField("New password", text: $new)
                    SecureField("Confirm new password", text: $confirm)
                }
                if !confirm.isEmpty && confirm != new {
                    Text("Passwords don't match yet.").font(.footnote).foregroundStyle(.orange)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                if didSucceed {
                    Label("Password changed.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(current.isEmpty || new.count < 8 || new != confirm)
                    }
                }
            }
        }
    }

    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await appState.changePassword(current: current, new: new)
            didSucceed = true
            current = ""; new = ""; confirm = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ProfileView()
        .environment(AppState())
        .environment(AppSettings.shared)
}
