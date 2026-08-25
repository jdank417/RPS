//
//  DisclaimerView.swift
//  RPS
//
//  The map key / about screen, adapted from the reference app's
//  info-panel.component: explains the mark-color legend and course symbols,
//  and carries the on-the-water disclaimer from the reference README.
//

import SwiftUI

struct DisclaimerView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Mark colours") {
                    legendRow(code: "R", color: .classify(govtLight: "R", isPortable: false), text: "Red — a nun or red light. Keep it to starboard coming in from seaward.")
                    legendRow(code: "G", color: .classify(govtLight: "G", isPortable: false), text: "Green — a can or green light. Keep it to port coming in from seaward.")
                    legendRow(code: "RG", color: .classify(govtLight: "RG", isPortable: false), text: "Red-and-green bands — a junction buoy. The top band is the preferred channel.")
                    legendRow(code: "RW", color: .classify(govtLight: "RW", isPortable: false), text: "Red-and-white stripes — a safe-water mark, deep water all round it.")
                    legendRow(code: "Y", color: .classify(govtLight: "Y", isPortable: false), text: "Yellow — a special mark. No navigational meaning; it marks an area.")
                    legendRow(code: "Or", color: .orange, text: "Orange — a racing barrel the club lays, not a government buoy.")
                    legendRow(code: "W", color: .white, text: "White — a white special or regulatory buoy.")
                    legendRow(code: "F", color: .neutral, text: "Blue — no colour on the chart. Either a portable mark the RC sets on the day, or a charted mark whose colour isn't recorded in the club's list.")
                }

                Section("Course symbols") {
                    HStack(spacing: 14) {
                        MarkBadge(code: "D", govtLight: nil, portable: false, isStart: true, size: 30)
                        Text("The mark the course starts from. It keeps its own code and colour.")
                            .font(.footnote)
                    }
                    HStack(spacing: 14) {
                        HStack(spacing: 4) {
                            roundTag("S", color: .green)
                            roundTag("P", color: .red)
                        }
                        Text("Rounding: S = leave to starboard, P = leave to port")
                            .font(.footnote)
                    }
                    HStack(spacing: 14) {
                        Image(systemName: "location.north.fill").foregroundStyle(.blue)
                        Text("Your GPS position and heading.")
                            .font(.footnote)
                    }
                    HStack(spacing: 14) {
                        Rectangle().fill(Color.orange).frame(width: 30, height: 4)
                        Text("The leg currently selected in the navigator.")
                            .font(.footnote)
                    }
                }

                Section("Where the marks come from") {
                    Text("Marks come from your club's mark list, as maintained in the club admin console.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text(disclaimerText)
                        .font(.footnote.italic())
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Map Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private let disclaimerText = """
    Always confirm marks and the course against the official Sailing \
    Instructions / Race Committee signals before racing. Positions for \
    portable marks are set on the water and are not fixed until placed \
    here.
    """

    private func legendRow(code: String, color: MarkColor, text: String) -> some View {
        HStack(spacing: 14) {
            Circle()
                .fill(color.solid)
                .frame(width: 26, height: 26)
                .overlay(Text(code).font(.system(size: 9, weight: .heavy)).foregroundStyle(color.foreground))
            Text(text).font(.footnote)
        }
    }

    private func roundTag(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color, in: Circle())
    }
}

#Preview {
    DisclaimerView()
}
