//
//  MarkListPickerSheet.swift
//  RPS
//
//  Lets the sailor browse the club's mark lists (its own list, or a shared
//  regional one) and switch which one the builder is working from.
//

import SwiftUI

struct MarkListPickerSheet: View {
    let markLists: [MarkList]
    let selectedId: UUID?
    let onSelect: (MarkList) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(markLists) { list in
                Button {
                    onSelect(list)
                    dismiss()
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
                        if list.id == selectedId {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Mark Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if markLists.isEmpty {
                    ContentUnavailableView("No mark lists", systemImage: "list.bullet")
                }
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
}
