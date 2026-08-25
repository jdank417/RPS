//
//  RaceModeView.swift
//  RPS
//
//  The race dashboard: leg navigator, live instruments (SOG/COG/VMG/wind),
//  start-line pinging with bias/approach, the start-sequence countdown, and
//  the course map with the boat overlaid — switched via a top segmented
//  control so each stays a full-screen, glanceable page.
//

import SwiftUI

struct RaceModeView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case leg = "Leg"
        case instruments = "Instruments"
        case start = "Start Line"
        case countdown = "Countdown"
        case map = "Map"
        var id: String { rawValue }
    }

    @Environment(RaceViewModel.self) private var race
    @Environment(LivePositionStore.self) private var liveStore
    @State private var segment: Segment = .countdown

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $segment) {
                    ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], 12)

                if let error = liveStore.error {
                    Label(error, systemImage: "location.slash.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                Group {
                    switch segment {
                    case .leg: LegNavigatorView()
                    case .instruments: InstrumentsView()
                    case .start: StartLineView()
                    case .countdown: StartSequenceView()
                    case .map: raceMap
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Race Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        liveStore.toggle()
                    } label: {
                        Label(liveStore.tracking ? "Stop GPS" : "Start GPS", systemImage: liveStore.tracking ? "location.fill" : "location.slash")
                    }
                    .tint(liveStore.tracking ? .green : .secondary)
                }
            }
        }
        .onAppear { liveStore.start() }
        .onChange(of: liveStore.fix) { _, _ in race.refreshWindIfNeeded() }
    }

    private var raceMap: some View {
        CourseMapView(
            mapPoints: race.courseStore.legComputation.mapPoints,
            liveFix: liveStore.fix,
            pin: race.pin,
            committee: race.committee,
            highlightedLegIndex: race.courseStore.currentLegIndex
        )
        .ignoresSafeArea(edges: .bottom)
    }
}

/// SOG/COG plus VMG-to-next-mark and true-wind-angle/tack/point-of-sail.
private struct InstrumentsView: View {
    @Environment(RaceViewModel.self) private var race
    @Environment(LivePositionStore.self) private var liveStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    bigReadout("SOG", value: liveStore.fix?.speedKts.map { String(format: "%.1f", $0) } ?? "—", unit: "kts")
                    bigReadout("COG", value: liveStore.fix?.headingDeg.map { GeoMath.fmtHeading($0) } ?? "—", unit: "true")
                }
                HStack(spacing: 16) {
                    bigReadout("VMG", value: race.vmgToMark.map { String(format: "%.1f", $0) } ?? "—", unit: "kts to mark")
                    bigReadout("RANGE", value: race.vector.map { String(format: "%.2f", $0.distNm) } ?? "—", unit: "nm")
                }

                windCard

                if let vector = race.vector, let off = vector.offCourseDeg {
                    Text(off < 0 ? "Mark is \(Int(-off))° to port" : "Mark is \(Int(off))° to starboard")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private var windCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Forecast wind", systemImage: "wind")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if race.windService.wind != nil {
                    Text(race.windService.stale ? "stale · \(race.windService.ageText)" : race.windService.ageText)
                        .font(.caption)
                        .foregroundStyle(race.windService.stale ? .orange : .secondary)
                }
            }
            if let wind = race.windService.wind {
                HStack(spacing: 20) {
                    VStack {
                        Text("\(Int(wind.fromDeg.rounded()))°").font(.title2.weight(.bold)).monospacedDigit()
                        Text(race.windCompassPoint ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack {
                        Text(String(format: "%.0f", wind.speedKts)).font(.title2.weight(.bold)).monospacedDigit()
                        Text("kts").font(.caption).foregroundStyle(.secondary)
                    }
                    if let tack = race.tack {
                        VStack {
                            Text(tack == .port ? "PORT" : "STBD")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(tack == .port ? .red : .green)
                            Text(race.pointOfSail ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No forecast wind yet — needs a GPS fix.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Model forecast, not a masthead reading.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func bigReadout(_ title: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary).tracking(1.5)
            Text(value).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Start-line pinging and live bias/over-line/time-to-line readouts.
private struct StartLineView: View {
    @Environment(RaceViewModel.self) private var race
    @Environment(LivePositionStore.self) private var liveStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    pingButton("Ping Pin", systemImage: "mappin.circle.fill", isSet: race.pin != nil) { race.pingPin() }
                    pingButton("Ping Committee Boat", systemImage: "flag.circle.fill", isSet: race.committee != nil) { race.pingCommittee() }
                }
                if race.pin != nil || race.committee != nil {
                    Button(role: .destructive) { race.clearLine() } label: {
                        Text("Clear Line").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let bias = race.lineBias {
                    biasCard(bias)
                } else {
                    Text("Ping both ends of the line to see bias. The wind direction is inferred from the first leg, so plot a course first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }

                if let approach = race.lineApproach {
                    approachCard(approach)
                }
            }
            .padding()
        }
    }

    private func pingButton(_ title: String, systemImage: String, isSet: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage).font(.title)
                Text(title).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
        }
        .buttonStyle(.borderedProminent)
        .tint(isSet ? .green : .accentColor)
        .disabled(liveStore.fix == nil)
    }

    private func biasCard(_ bias: StartLine.LineBias) -> some View {
        VStack(spacing: 8) {
            Text(favouredText(bias))
                .font(.title2.weight(.bold))
            Text(String(format: "Line length %.0fm, %.0f%% off square", bias.lengthM, min(abs(bias.biasDeg) / 90 * 100, 100)))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func favouredText(_ bias: StartLine.LineBias) -> String {
        switch bias.favoured {
        case .square: return "Line is square"
        case .pin: return String(format: "Pin favoured by %.0fm", bias.advantageM)
        case .committee: return String(format: "Committee boat favoured by %.0fm", bias.advantageM)
        }
    }

    private func approachCard(_ approach: StartLine.LineApproach) -> some View {
        VStack(spacing: 8) {
            Text(approach.over ? "OVER THE LINE" : String(format: "%.0fm to the line", approach.distanceM))
                .font(.title2.weight(.bold))
                .foregroundStyle(approach.over ? .red : .primary)
            if let t = approach.timeToLineSec {
                Text(String(format: "%.0fs to burn", t))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background((approach.over ? Color.red : Color.green).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    let courseStore = CourseStateStore()
    let liveStore = LivePositionStore()
    let wind = WindService()
    RaceModeView()
        .environment(RaceViewModel(courseStore: courseStore, liveStore: liveStore, windService: wind))
        .environment(liveStore)
        .environment(courseStore)
}
