//
//  ClubPickerView.swift
//  RPS
//
//  Shown when bootstrap comes back with no resolved home club and more than
//  one club to choose from. Sets `home_club_id` via PATCH /users/me, then
//  re-bootstraps against the chosen club.
//

import SwiftUI

struct ClubPickerView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var selecting: YachtClub?
    @State private var errorMessage: String?

    private var clubs: [YachtClub] {
        appState.bootstrap?.clubs ?? []
    }

    private var filtered: [YachtClub] {
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
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }
                Section {
                    ForEach(filtered) { club in
                        Button {
                            Task { await choose(club) }
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
                                if selecting?.id == club.id {
                                    ProgressView()
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .disabled(selecting != nil)
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
            .navigationTitle("Choose your club")
            .navigationBarTitleDisplayMode(.large)
            .overlay {
                if clubs.isEmpty {
                    ContentUnavailableView("No clubs available", systemImage: "flag.slash")
                }
            }
        }
    }

    private func choose(_ club: YachtClub) async {
        selecting = club
        errorMessage = nil
        do {
            try await appState.selectHomeClub(club)
        } catch {
            errorMessage = error.localizedDescription
        }
        selecting = nil
    }
}

/// Renders a club's burgee if it were vector art the app trusted enough to
/// inline; for v1 this is always the initials-badge fallback, since the API
/// hands back raw SVG markup which SwiftUI has no first-party renderer for.
struct BurgeeBadge: View {
    let club: YachtClub
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(club.initials.isEmpty ? "?" : club.initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }

    private var color: Color {
        let hues: [Color] = [.blue, .teal, .indigo, .cyan, .mint, .purple]
        // `abs(Int.min)` traps, so wrap into a non-negative index instead of
        // taking the absolute value of a hash that could be anything.
        let index = ((club.slug.hashValue % hues.count) + hues.count) % hues.count
        return hues[index]
    }
}

#Preview {
    ClubPickerView()
        .environment(AppState())
}
