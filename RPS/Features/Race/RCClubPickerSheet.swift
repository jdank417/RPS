//
//  RCClubPickerSheet.swift
//  RPS
//
//  Two-step flow for picking which club is running race committee (RC) — not
//  the same as the sailor's home club. Step 1: pick an RC club. Step 2: pick
//  that club's mark list. This is a per-session choice that survives app
//  relaunch but isn't written back to the user's profile.
//

import SwiftUI

struct RCClubPickerSheet: View {
    let onSelect: (YachtClub, MarkList, [Mark]) async throws -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var clubs: [YachtClub] = []
    @State private var selectedClub: YachtClub?
    @State private var markLists: [MarkList] = []
    @State private var isLoadingClubs = false
    @State private var isLoadingMarkLists = false
    @State private var errorMessage: String?
    @State private var query = ""
    
    private var filteredClubs: [YachtClub] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return clubs }
        let q = query.lowercased()
        return clubs.filter {
            $0.name.lowercased().contains(q)
                || ($0.region?.lowercased().contains(q) ?? false)
                || ($0.country?.lowercased().contains(q) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if selectedClub == nil {
                    clubList
                } else {
                    markListView
                }
            }
            .navigationTitle(selectedClub == nil ? "Choose RC Club" : "Mark Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if selectedClub != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { selectedClub = nil; markLists = [] }
                    }
                }
            }
        }
        .task {
            await loadClubs()
        }
    }
    
    private var clubList: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            
            Section {
                ForEach(filteredClubs) { club in
                    Button {
                        Task { await selectClub(club) }
                    } label: {
                        HStack(spacing: 14) {
                            BurgeeBadge(club: club)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(club.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                if let region = club.region {
                                    Text([region, club.country].compactMap { $0 }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isLoadingMarkLists && selectedClub?.id == club.id {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .disabled(isLoadingMarkLists)
                }
                
                Link(destination: URL(string: "https://rps-admin-frontend.onrender.com/request-club")!) {
                    HStack {
                        Label("Don't see your club? Get it set up", systemImage: "plus.circle")
                            .font(.body)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.tint)
            }
        }
        .searchable(text: $query, prompt: "Search clubs")
        .overlay {
            if isLoadingClubs {
                ProgressView()
            } else if clubs.isEmpty {
                ContentUnavailableView("No clubs available", systemImage: "flag.slash")
            }
        }
    }
    
    private var markListView: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }
            
            if let club = selectedClub {
                Section {
                    ForEach(markLists) { list in
                        Button {
                            Task { await selectMarkList(club: club, list: list) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(list.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        scopeBadge(list.scope)
                                        if let label = list.sourceLabel {
                                            Text(label).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text(club.name)
                }
            }
        }
        .overlay {
            if isLoadingMarkLists {
                ProgressView()
            } else if markLists.isEmpty {
                ContentUnavailableView("No mark lists", systemImage: "list.bullet")
            }
        }
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
    
    private func loadClubs() async {
        guard clubs.isEmpty else { return }
        isLoadingClubs = true
        errorMessage = nil
        defer { isLoadingClubs = false }
        do {
            clubs = try await APIClient.shared.clubs()
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
        do {
            let marks = try await APIClient.shared.marks(markListId: list.id)
            try await onSelect(club, list, marks)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
