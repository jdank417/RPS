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
    enum Segment: String, CaseIterable, Identifiable {
        case leg = "Leg"
        case instruments = "Instruments"
        case start = "Start Line"
        case countdown = "Countdown"
        case map = "Map"
        var id: String { rawValue }

        /// Five segments of text ("Instruments", "Countdown", "Start Line")
        /// do not fit across an iPhone - they truncate to ellipses and the
        /// control reads as cramped. Icons fit comfortably at a full tap
        /// target each; the navigation title carries the name of whichever
        /// one is selected, so nothing is actually lost.
        var symbol: String {
            switch self {
            case .leg: return "arrow.triangle.turn.up.right.diamond"
            case .instruments: return "gauge.with.dots.needle.bottom.50percent"
            case .start: return "flag.checkered"
            case .countdown: return "timer"
            case .map: return "map"
            }
        }
    }

    @Environment(RaceViewModel.self) private var race
    @Environment(LivePositionStore.self) private var liveStore
    @Environment(TidalCurrentService.self) private var tidalService
    @Environment(StartSequenceViewModel.self) private var sequence
    @Environment(RaceLiveActivityManager.self) private var liveActivity
    @Binding var selectedSegment: Segment

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedSegment) {
                    ForEach(Segment.allCases) { segment in
                        Image(systemName: segment.symbol)
                            .accessibilityLabel(segment.rawValue)
                            .tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

                if let error = liveStore.error {
                    Label(error, systemImage: "location.slash.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                Group {
                    switch selectedSegment {
                    case .leg: LegNavigatorView()
                    case .instruments: InstrumentsView()
                    case .start: StartLineView()
                    case .countdown: StartSequenceView()
                    case .map: raceMap
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(selectedSegment.rawValue)
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
        // Not userInitiated: if the sailor deliberately stopped GPS, coming
        // back to this tab must not silently restart it.
        .onAppear {
            liveStore.start(userInitiated: false)
            syncLiveActivity()
        }
        .onChange(of: liveStore.fix) { _, fix in
            race.refreshWindIfNeeded()
            if let fix {
                Task { await tidalService.refresh(lat: fix.lat, lon: fix.lon) }
            }
            syncLiveActivity()
        }
        // Ticks every 250ms while a sequence is armed - cheap to call this
        // often since RaceLiveActivityManager only actually pushes to the
        // system when something worth showing has changed.
        .onChange(of: sequence.secondsToStart) { _, _ in syncLiveActivity() }
    }

    /// Mirrors the start sequence's own lifecycle onto the Lock Screen:
    /// armed means started, stopped means ended. Leg/bearing/wind come
    /// from whatever the race view model can currently derive from the
    /// live fix - nil once there's no fix or no leg being sailed yet,
    /// which the activity's view already handles by simply not showing
    /// that row.
    private func syncLiveActivity() {
        var legLabel: String?
        if let idx = race.courseStore.currentLegIndex, let leg = race.courseStore.legComputation.legs[safe: idx] {
            legLabel = "\(leg.fromLabel) → \(leg.toLabel)"
        }

        liveActivity.sync(
            clubName: race.courseStore.rcClubName ?? race.courseStore.rcListName ?? "RPS",
            running: sequence.running,
            startAt: sequence.startAt,
            flag: sequence.flag,
            isRacing: sequence.phase == .racing,
            legLabel: legLabel,
            distNm: race.vector?.distNm,
            bearingTrue: race.vector?.bearingTrue,
            windFromDeg: race.windService.wind?.fromDeg,
            windSpeedKts: race.windService.wind?.speedKts
        )
    }

    /// Height the leg toolbar occupies, handed to the map so it insets its
    /// content above it rather than plotting marks underneath it.
    private let legToolbarHeight: CGFloat = 108

    private var raceMap: some View {
        let computation = race.courseStore.legComputation
        return CourseMapView(
            mapPoints: computation.mapPoints,
            liveFix: liveStore.fix,
            pin: race.pin,
            committee: race.committee,
            highlightedLegIndex: race.courseStore.currentLegIndex,
            windFromDeg: race.windService.wind?.fromDeg,
            current: tidalService.snapshot?.current,
            bottomContentInset: computation.legs.isEmpty ? 0 : legToolbarHeight
        )
        // safeAreaInset rather than a ZStack overlay: this keeps the toolbar
        // clear of the tab bar and home indicator instead of sitting on top
        // of them, which is what made the map feel cramped.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !computation.legs.isEmpty {
                legToolbar(legs: computation.legs)
            }
        }
    }

    @ViewBuilder
    private func legToolbar(legs: [LegInfo]) -> some View {
        if let currentIndex = race.courseStore.currentLegIndex, let leg = legs[safe: currentIndex] {
            HStack(spacing: 8) {
                stepButton(systemImage: "chevron.left", label: "Previous leg") {
                    race.courseStore.setCurrentLeg(currentIndex - 1)
                }
                .disabled(currentIndex == 0)

                VStack(spacing: 5) {
                    Text("LEG \(leg.legIndex + 1) OF \(legs.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    Text("\(leg.fromLabel) → \(leg.toLabel)")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 18) {
                        if let hdg = leg.magHdg ?? leg.trueHdg {
                            Label(GeoMath.fmtHeading(hdg), systemImage: "location.north.fill")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        if let dist = leg.distNm {
                            Label(String(format: "%.2f nm", dist), systemImage: "ruler")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                stepButton(systemImage: "chevron.right", label: "Next leg") {
                    race.courseStore.setCurrentLeg(currentIndex + 1)
                }
                .disabled(currentIndex >= legs.count - 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(height: legToolbarHeight)
            .background(.ultraThinMaterial)
        }
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

/// SOG/COG plus VMG-to-next-mark and true-wind-angle/tack/point-of-sail.
private struct InstrumentsView: View {
    @Environment(RaceViewModel.self) private var race
    @Environment(LivePositionStore.self) private var liveStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                gpsStatusCard

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

    /// What the GPS receiver is actually doing.
    ///
    /// "GPS doesn't work" covers at least three unrelated failures - the
    /// permission was never requested, it was refused, or it is granted and
    /// simply hasn't got a fix yet - and they need different fixes. Showing
    /// which one it is turns an unreproducible report into an obvious one.
    private var gpsStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("GPS", systemImage: gpsIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(gpsTint)
                Spacer()
                Button(liveStore.tracking ? "Stop" : "Start") { liveStore.toggle() }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text(liveStore.statusDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let fix = liveStore.fix {
                Text(String(format: "%.5f, %.5f", fix.lat, fix.lon))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    if let acc = fix.accuracyM {
                        Text(String(format: "±%.0f m", acc)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("\(liveStore.fixCount) fixes").font(.caption2).foregroundStyle(.secondary)
                }
            }

            if liveStore.isDenied {
                Button {
                    liveStore.openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var gpsIcon: String {
        if liveStore.isDenied { return "location.slash.fill" }
        if liveStore.fix != nil { return "location.fill" }
        return liveStore.tracking ? "location.circle" : "location.slash"
    }

    private var gpsTint: Color {
        if liveStore.isDenied { return .red }
        return liveStore.fix != nil ? .green : .orange
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

    private var startIsChartedMark: Bool { race.courseStore.startIsChartedMark }

    /// "Clear Line" only makes sense for something that was pinged. A
    /// charted pin isn't pinged data — there's nothing there to clear, and
    /// it stays put regardless — so it doesn't keep the button around on
    /// its own.
    private var canClearLine: Bool {
        race.committee != nil || (!startIsChartedMark && race.pin != nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if startIsChartedMark {
                    chartedPinCard
                    pingButton("Ping Committee Boat", systemImage: "flag.circle.fill", isSet: race.committee != nil) { race.pingCommittee() }
                } else {
                    HStack(spacing: 12) {
                        pingButton("Ping Pin", systemImage: "mappin.circle.fill", isSet: race.pin != nil) { race.pingPin() }
                        pingButton("Ping Committee Boat", systemImage: "flag.circle.fill", isSet: race.committee != nil) { race.pingCommittee() }
                    }
                }

                if canClearLine {
                    Button(role: .destructive) { race.clearLine() } label: {
                        Text("Clear Line").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if let bias = race.lineBias {
                    biasCard(bias)
                } else {
                    Text(startIsChartedMark
                        ? "Ping the committee boat to see bias. The wind direction is inferred from the first leg, so plot a course first."
                        : "Ping both ends of the line to see bias. The wind direction is inferred from the first leg, so plot a course first.")
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

    /// The charted mark standing in as the pin end — no ping needed, just a
    /// statement of what it is.
    private var chartedPinCard: some View {
        VStack(spacing: 6) {
            Label(chartedPinLabel, systemImage: "mappin.circle.fill")
                .font(.headline)
            Text("Pin end is a charted mark — its position is already known.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var chartedPinLabel: String {
        guard let entry = race.courseStore.startEntry else { return "Pin" }
        return "\(entry.mark.code) — \(entry.mark.name)"
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    @Previewable @State var segment: RaceModeView.Segment = .countdown
    let courseStore = CourseStateStore()
    let liveStore = LivePositionStore()
    let wind = WindService()
    RaceModeView(selectedSegment: $segment)
        .environment(RaceViewModel(courseStore: courseStore, liveStore: liveStore, windService: wind))
        .environment(liveStore)
        .environment(courseStore)
        .environment(TidalCurrentService())
        .environment(StartSequenceViewModel())
        .environment(RaceLiveActivityManager())
}
