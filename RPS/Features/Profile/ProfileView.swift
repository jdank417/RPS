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
    @State private var showDeleteAccount = false
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

                Section {
                    Picker("Headings", selection: Binding(
                        get: { settings.useMagnetic },
                        set: { settings.useMagnetic = $0 }
                    )) {
                        Text("True").tag(false)
                        Text("Magnetic").tag(true)
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Magnetic variation", value: String(format: "%.1f°", settings.variationDeg))
                } header: {
                    Text("Headings")
                } footer: {
                    Text(
                        settings.useMagnetic
                            ? "Leg headings show magnetic first, with true underneath. Wind angles are still worked out in degrees true."
                            : "Leg headings show true first, with magnetic underneath — matching the wind forecast and start-line bias, which are both in degrees true."
                    )
                }

                Section("App") {
                    Button("Server Settings") { showServerSettings = true }
                    Button("Map Key & Disclaimer") { showInfo = true }
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

                // Its own section, below Sign Out and behind a password, so
                // it can't be reached by a thumb aiming for something else.
                // App Store Review guideline 5.1.1(v) requires this to exist
                // in the app, not just as an email to support.
                Section {
                    Button(role: .destructive) {
                        showDeleteAccount = true
                    } label: {
                        Text("Delete Account").frame(maxWidth: .infinity)
                    }
                } footer: {
                    Text(
                        "Permanently deletes your account and your club-admin access. "
                        + "Marks and mark lists belong to the club and stay. This can't be undone."
                    )
                }
            }
            .navigationTitle("Profile")
            .onAppear { fullName = appState.currentUser?.fullName ?? "" }
            .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await appState.signOut() } }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountView()
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

/// Account deletion, per App Store Review guideline 5.1.1(v).
///
/// Two things stand between a tap and a deleted account: the password, and
/// a confirmation dialog. That is deliberate for an action with no undo -
/// there is no "deleted accounts" list to restore from, and re-registering
/// the same email produces a genuinely new, empty account.
private struct DeleteAccountView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Deleting your account removes your sign-in, your club-admin access, "
                         + "and your upload history.")
                    Text("Marks and mark lists belong to the club, not to you, so they stay "
                         + "where they are.")
                    Text("This can't be undone.")
                        .fontWeight(.semibold)
                }

                Section("Confirm your password") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showConfirm = true
                    } label: {
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Delete My Account").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(password.isEmpty || isLoading)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isLoading)
                }
            }
            .confirmationDialog(
                "Permanently delete your account?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func deleteAccount() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await appState.deleteAccount(password: password)
            // No dismiss() needed: AppState.phase is now .signedOut, so
            // RootView swaps the whole tab bar out from under this sheet for
            // the sign-in screen.
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
