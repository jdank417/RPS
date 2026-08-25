//
//  RCClubPickerSheet.swift
//  RPS
//
//  Two-step flow for picking which club is running race committee (RC) - not
//  the same as the sailor's home club. Step 1: pick an RC club. Step 2: pick
//  that club's mark list. This is a per-session choice that survives app
//  relaunch but is never written back to the user's profile.
//
//  A sailor at a BYC Wednesday one week and a JYC Thursday the next is
//  racing off two different clubs' marks with the same home club, which is
//  exactly why this is separate from `home_club_id`.
//

import SwiftUI

struct RCClubPickerSheet: View {
    var currentClubSlug: String?
    var currentListId: UUID?
    /// When set, the sheet opens straight on that club's mark lists. Used by
    /// "Switch mark list", which is about changing the list within the club
    /// already running the race, not about changing the club.
    var initialClub: YachtClub?
    let onSelect: (YachtClub, MarkList, [Mark]) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var clubs: [YachtClub] = []
    @State private var selectedClub: YachtClub?
    @State private var didApplyInitialClub = false
    @State private var markLists: [MarkList] = []
    @State private var isLoadingClubs = false
    @State private var isLoadingMarkLists = false
    @State private var loadingListId: UUID?
    @State private var errorMessage: String?
    @State private var query = ""

    private var filteredClubs: [YachtClub] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return clubs }
        return clubs.filter {
            $0.name.lowercased().contains(trimmed)
                || ($0.region?.lowercased().contains(trimmed) ?? false)
                || ($0.country?.lowercased().contains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let club = selectedClub {
                    markListStep(club: club)
                } else {
                    clubStep
                }
            }
            .navigationTitle(selectedClub == nil ? "Race Committee" : "Mark List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Back replaces Close on step two rather than sitting beside
                // it - two leading buttons collided in the nav bar.
                ToolbarItem(placement: .topBarLeading) {
                    if selectedClub == nil {
                        Button("Close") { dismiss() }
                    } else {
                        Button {
                            selectedClub = nil
                            markLists = []
                            errorMessage = nil
                        } label: {
                            Label("Clubs", systemImage: "chevron.left")
                        }
                    }
                }
            }
        }
        .task {
            if let initialClub, !didApplyInitialClub {
                didApplyInitialClub = true
                await selectClub(initialClub)
            }
            await loadClubs()
        }
    }

    // MARK: - Step one: the club

    private var clubStep: some View {
        List {
            if let errorMessage {
                Section { errorRow(errorMessage) }
            }

            Section {
                ForEach(filteredClubs) { club in
                    Button {
                        Task { await selectClub(club) }
                    } label: {
                        HStack(spacing: 14) {
                            BurgeeBadge(club: club)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(club.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                if let subtitle = locationLine(club) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            if isLoadingMarkLists && selectedClub?.id == club.id {
                                ProgressView()
                            } else if club.slug == currentClubSlug {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(isLoadingMarkLists)
                }
            } header: {
                Text("Which club is running today's race?")
            }

            Section {
                Link(destination: URL(string: "https://rps-admin-frontend.onrender.com/request-club")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17))
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Don't see your club?")
                                .font(.body.weight(.medium))
                            Text("Get it set up on RPS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .searchable(text: $query, prompt: "Search clubs")
        .overlay {
            if clubs.isEmpty {
                if isLoadingClubs {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No clubs available",
                        systemImage: "flag.slash",
                        description: Text("Pull down to retry, or check your connection.")
                    )
                }
            } else if filteredClubs.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .refreshable { await loadClubs(force: true) }
    }

    // MARK: - Step two: the list

    private func markListStep(club: YachtClub) -> some View {
        List {
            if let errorMessage {
                Section { errorRow(errorMessage) }
            }

            Section {
                ForEach(markLists) { list in
                    Button {
                        Task { await selectMarkList(club: club, list: list) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                HStack(spacing: 6) {
                                    scopeBadge(list.scope)
                                    if let label = list.sourceLabel {
                                        Text(label)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer(minLength: 8)
                            if loadingListId == list.id {
                                ProgressView()
                            } else if list.id == currentListId {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .disabled(loadingListId != nil)
                }
            } header: {
                Text(club.name)
            } footer: {
                Text("“Club” lists belong to this club's own series. “Regional” lists are shared standard courses used by several clubs.")
            }
        }
        .overlay {
            if isLoadingMarkLists {
                ProgressView()
            } else if markLists.isEmpty {
                ContentUnavailableView(
                    "No mark lists",
                    systemImage: "list.bullet",
                    description: Text("\(club.name) hasn't published any mark lists yet.")
                )
            }
        }
    }

    // MARK: - Pieces

    private func locationLine(_ club: YachtClub) -> String? {
        let parts = [club.region, club.country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func errorRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
    }

    @ViewBuilder
    private func scopeBadge(_ scope: MarkListScope) -> some View {
        Text(scope == .club ? "Club" : "Regional")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(scope == .club ? Color.accentColor.opacity(0.18) : Color.orange.opacity(0.18))
            .foregroundStyle(scope == .club ? Color.accentColor : Color.orange)
            .clipShape(Capsule())
    }

    // MARK: - Loading

    private func loadClubs(force: Bool = false) async {
        guard force || clubs.isEmpty else { return }
        isLoadingClubs = true
        errorMessage = nil
        defer { isLoadingClubs = false }
        do {
            clubs = try await APIClient.shared.clubs(forceRefresh: force)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectClub(_ club: YachtClub) async {
        selectedClub = club
        isLoadingMarkLists = true
        errorMessage = nil
        defer { isLoadingMarkLists = false }
        do {
            markLists = try await APIClient.shared.markLists(clubSlug: club.slug)
        } catch {
            errorMessage = error.localizedDescription
            selectedClub = nil
        }
    }

    private func selectMarkList(club: YachtClub, list: MarkList) async {
        errorMessage = nil
        loadingListId = list.id
        defer { loadingListId = nil }
        do {
            let marks = try await APIClient.shared.marks(markListId: list.id)
            try await onSelect(club, list, marks)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
