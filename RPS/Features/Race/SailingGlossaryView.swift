//
//  SailingGlossaryView.swift
//  RPS
//
//  Plain-language explanations for the sailing/instrument shorthand used
//  across Race Mode (SOG, COG, VMC, tack, rounding, line bias, ...) - a
//  sailor who knows the sport but not this jargon, or is new to instruments
//  altogether, shouldn't have to guess or ask someone else what a label
//  means. Reachable from Instruments, the Leg screen, and Start Line.
//

import SwiftUI

struct SailingGlossaryView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Term: Identifiable {
        let name: String
        let body: String
        var id: String { name }
    }

    private struct Section_: Identifiable {
        let title: String
        let terms: [Term]
        var id: String { title }
    }

    private let sections: [Section_] = [
        Section_(title: "Boat instruments", terms: [
            Term(name: "SOG — Speed Over Ground", body: "How fast the boat is actually moving right now, in knots, straight from GPS."),
            Term(name: "COG — Course Over Ground", body: "The direction the boat is actually traveling, from GPS. This can differ from where the bow is pointed if current or leeway is pushing the boat sideways."),
            Term(name: "VMC — Velocity Made good on Course", body: "How fast you're actually closing the distance to the next mark. It's normal for this to go negative while tacking upwind, even when you're sailing well — it isn't the same thing as boat speed."),
            Term(name: "RANGE", body: "The straight-line distance left to the mark you're currently sailing to."),
            Term(name: "LIVE HEADING", body: "The boat's real-time GPS course, shown alongside the planned heading so you can see at a glance whether you're actually laying the mark."),
            Term(name: "TRUE vs. MAGNETIC", body: "Two ways of expressing the same heading. True is measured against the geographic North Pole; magnetic is what a steering compass actually reads, offset by the local magnetic variation."),
        ]),
        Section_(title: "Wind", terms: [
            Term(name: "Tack: Port / Starboard", body: "Which side the wind is hitting first. On port tack, the wind comes over the left (port) side; on starboard, the right. Starboard tack has right of way."),
            Term(name: "Point of sail", body: "A plain description of your angle to the wind — close-hauled (as close to the wind as the boat will sail), reaching, or running (wind from behind)."),
        ]),
        Section_(title: "Start line", terms: [
            Term(name: "Ping", body: "Recording a GPS position by tapping a button while sitting at that exact spot — used to mark the pin end, the committee boat, or a mark the RC just set on the water."),
            Term(name: "Favoured end / bias", body: "Which end of the start line is closer to the first mark. Starting at the favoured end gives you a head start over boats at the other end."),
            Term(name: "% off square", body: "How far the start line is from sitting exactly perpendicular to the wind. 0% is a perfectly square line; higher numbers mean one end is more favoured."),
        ]),
        Section_(title: "Course", terms: [
            Term(name: "Rounding: S / P", body: "Which side you leave the mark on as you round it — starboard (S) or port (P) side to the boat. A hollow tag means the mark is following the race committee's general signal instead of having its own."),
            Term(name: "Twice around", body: "The course is sailed twice before finishing, signalled by the race committee flying code flag T."),
            Term(name: "Charted vs. portable mark", body: "A charted mark has a fixed, known position, like a permanent buoy. A portable mark is set by the race committee on the day and has no position until it's placed or pinged."),
        ]),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.terms) { term in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(term.name).font(.body.weight(.semibold))
                                Text(term.body).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Sailing Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SailingGlossaryView()
}
