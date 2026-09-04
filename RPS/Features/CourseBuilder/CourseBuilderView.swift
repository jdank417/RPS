//
//  CourseBuilderView.swift
//  RPS
//
//  Build an ordered course from the club's mark list: append marks, cycle
//  rounding per entry, mark the start, toggle twice-around, place
//  unpositioned/portable marks, and see legs recomputed live. Ported from the
//  reference app's course-builder page.
//

import SwiftUI
import CoreLocation

/// The course list's motion, named once so every edit to the course moves
/// the same way.
///
/// Declared as explicitly-typed `Animation` constants rather than written
/// inline as `.snappy(...)` at each call site: a leading-dot member lookup
/// inside `withAnimation` has to be resolved against the closure's return
/// type at the same time, and when that closure calls something returning a
/// value the type checker reports the failure against the *animation*
/// ("Ambiguous use of 'spring(duration:bounce:blendDuration:)'") rather than
/// the real cause. Giving the type up front removes that whole class of
/// misdirected error.
private enum CourseMotion {
    static let add: Animation = .snappy(duration: 0.28, extraBounce: 0.18)
    static let remove: Animation = .snappy(duration: 0.28, extraBounce: 0.1)
    static let rounding: Animation = .snappy(duration: 0.22, extraBounce: 0.2)
    static let start: Animation = .snappy(duration: 0.28, extraBounce: 0.2)
    static let reorder: Animation = .snappy(duration: 0.3, extraBounce: 0.15)
    static let list: Animation = .snappy(duration: 0.28, extraBounce: 0.15)
}

struct CourseBuilderView: View {
    @Environment(AppState.self) private var appState
    @Environment(CourseStateStore.self) private var course
    @Environment(LivePositionStore.self) private var liveFix

    @State private var showMarkListPicker = false
    @State private var showRCClubPicker = false
    @State private var showVariationSheet = false
    @State private var placingEntry: CourseEntry?
    @State private var isLoadingMarks = false
    @State private var errorMessage: String?
    /// Tracks a start-line choice the sailor just made in the UI before the
    /// store reflects it — picking "Charted mark" shows the mark picker
    /// immediately, without waiting on a mark to actually be chosen (which
    /// is the only thing that changes `course.startIsChartedMark`). Cleared
    /// once the store agrees, so the control never fights a later change
    /// made some other way (e.g. swiping a row to "Start").
    @State private var startChoiceOverride: StartLineChoice?

    var onPlotCourse: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                raceSection
                startLineSection
                signalsSection

                if let message = course.statusMessage {
                    Section {
                        Label(message, systemImage: course.statusIsError ? "exclamationmark.triangle.fill" : "info.circle")
                            .font(.footnote)
                            .foregroundStyle(course.statusIsError ? .red : .secondary)
                    }
                }

                courseSection
                paletteSection
            }
            .refreshable { await reloadMarks() }
            // A light tap when a mark lands in the course - the same
            // confirmation a physical control gives, which matters when the
            // phone is being used one-handed and half-watched.
            .sensoryFeedback(.impact(flexibility: .soft), trigger: course.course.count)
            .animation(CourseMotion.list, value: course.course)
            .navigationTitle(markListName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if !course.course.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Twice around", isOn: Binding(
                            get: { course.twiceAround },
                            set: { _ in course.toggleTwiceAround() }
                        ))
                        Button {
                            showVariationSheet = true
                        } label: {
                            Label("Magnetic variation: \(course.variationDeg, specifier: "%.1f")°", systemImage: "location.north.line")
                        }
                        Button(role: .destructive) {
                            course.resetCourse()
                        } label: {
                            Label("Clear course", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { summaryBar }
            // Same picker for both entry points; "Switch mark list" just
            // opens it already on the current club's lists. Pointing that
            // button at the *home* club's lists, as it used to, was wrong the
            // moment a different club was running the race.
            .sheet(isPresented: $showMarkListPicker) {
                rcPicker(initialClub: currentRCClub)
            }
            .sheet(isPresented: $showRCClubPicker) {
                rcPicker(initialClub: nil)
            }
            .sheet(isPresented: $showVariationSheet) {
                VariationSheet(variationDeg: course.variationDeg) { course.setVariationDeg($0) }
            }
            .sheet(item: $placingEntry) { entry in
                PositionEntrySheet(
                    markLabel: entry.mark.code,
                    initial: resolvedPosition(entry).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                    liveFix: liveFix.coordinate
                ) { lat, lon, source in
                    course.choosePositionTarget(uid: entry.uid)
                    course.applyPosition(lat: lat, lon: lon, sourceLabel: source)
                }
            }
            .task { await loadInitialMarksIfNeeded() }
        }
    }

    // MARK: - Pickers

    /// The club currently running the race: the explicitly-chosen RC club if
    /// there is one, otherwise the sailor's own club from bootstrap.
    private var currentRCClub: YachtClub? {
        if let slug = course.rcClubSlug {
            return appState.bootstrap?.clubs.first { $0.slug == slug }
        }
        return appState.bootstrap?.club
    }

    private func rcPicker(initialClub: YachtClub?) -> some View {
        RCClubPickerSheet(
            currentClubSlug: course.rcClubSlug ?? appState.bootstrap?.club?.slug,
            currentListId: activeMarkListId,
            initialClub: initialClub
        ) { club, list, marks in
            course.setRCClub(slug: club.slug, name: club.name, listName: list.name)
            // Marks from another club aren't meaningful in this one, so
            // setActiveMarks clears the course unless it's the same list;
            // restoreFor then brings back a course saved against this list.
            let sameList = course.activeMarkListId == list.id
            course.setActiveMarks(marks, keepCourse: sameList)
            course.setMarkListId(list.id)
            if !sameList { course.restoreFor(markListId: list.id) }
        }
    }

    // MARK: - Sections

    /// Who is running the race, and off which list. Deliberately the first
    /// thing in the builder rather than a toolbar icon: picking the wrong
    /// club's marks is the one mistake here that produces a plausible-looking
    /// course made of the wrong buoys, so it needs to be visible without
    /// being looked for.
    private var raceSection: some View {
        Section {
            Button {
                showRCClubPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "flag.2.crossed.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.tint)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("RACE COMMITTEE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                        Text(course.rcClubName ?? appState.bootstrap?.club?.name ?? "Choose a club")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let listName = course.rcListName ?? bootstrapListName {
                            Text(listName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
            }

            Button {
                showMarkListPicker = true
            } label: {
                Label("Switch mark list", systemImage: "list.bullet.rectangle")
                    .font(.subheadline)
            }
        } footer: {
            Text("Set which club is running today's race — their marks and series lists load here. This is separate from your home club.")
        }
    }

    private var bootstrapListName: String? {
        appState.bootstrap?.markLists.first { $0.id == activeMarkListId }?.name
    }

    /// Whether the pin end of the start line is a fixed, charted mark or
    /// something to be pinged live. Asked up front, near the top of the
    /// builder, because it changes what Race Mode's start-line panel offers
    /// later: a charted mark's position is already known, so only the
    /// committee boat — a boat, not a fixed object — genuinely needs a ping.
    private enum StartLineChoice: Hashable { case charted, ping }

    private var startLineChoice: StartLineChoice {
        startChoiceOverride ?? (course.startIsChartedMark ? .charted : .ping)
    }

    private var startLineChoiceBinding: Binding<StartLineChoice> {
        Binding(
            get: { startLineChoice },
            set: { newValue in
                startChoiceOverride = newValue
                if newValue == .ping {
                    withAnimation(CourseMotion.start) { course.setStartToPing() }
                    startChoiceOverride = nil
                }
            }
        )
    }

    /// Charted marks with a known position — the only marks that can stand
    /// in as a fixed pin end. Portable marks have nothing to pick: their
    /// whole point is that the RC sets them on the day.
    private var chartedStartCandidates: [Mark] {
        course.activeMarks.filter { !$0.portable && $0.lat != nil && $0.lon != nil }
    }

    private var chartedStartMarkBinding: Binding<Mark?> {
        Binding(
            get: { course.startIsChartedMark ? course.startEntry?.mark : nil },
            set: { newValue in
                guard let newValue else { return }
                withAnimation(CourseMotion.start) {
                    if course.setStartFromMark(newValue) {
                        startChoiceOverride = nil
                    }
                }
            }
        )
    }

    /// The government number is physically printed on the buoy, so it's what
    /// a sailor standing next to it can actually check against - the code
    /// and name alone assume you already trust the chart.
    private func pinMarkLabel(_ mark: Mark) -> String {
        var label = "\(mark.code) — \(mark.name)"
        if let govNumber = mark.govNumber, !govNumber.isEmpty {
            label += " (No. \(govNumber))"
        }
        return label
    }

    private var startLineSection: some View {
        Section {
            Picker("Where is the start line?", selection: startLineChoiceBinding) {
                Text("Charted mark").tag(StartLineChoice.charted)
                Text("Ping on the water").tag(StartLineChoice.ping)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if startLineChoice == .charted {
                if chartedStartCandidates.isEmpty {
                    Text("No marks in this list are charted with a fixed position.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Pin mark", selection: chartedStartMarkBinding) {
                        Text("Choose a mark").tag(Optional<Mark>.none)
                        ForEach(chartedStartCandidates) { mark in
                            Text(pinMarkLabel(mark)).tag(Optional(mark))
                        }
                    }
                }
            }
        } header: {
            Text("Start line")
        } footer: {
            Text(startLineChoice == .charted
                ? "The pin end is a fixed mark, so its name doesn't need to go on the course the way a turning mark's does — the RC never posts it either. In Race Mode only the committee boat needs pinging."
                : "The pin end will be pinged live from the boat in Race Mode, same as the committee boat.")
        }
    }

    /// What the RC is flying, as cloth you tap rather than settings you hunt
    /// for. Both of these were a single visible tap in the web app and had
    /// regressed here - the course-wide rounding had no control at all, and
    /// twice-around was hidden behind the overflow menu, which is the wrong
    /// place for something the RC can change between races.
    private var signalsSection: some View {
        Section {
            HStack(spacing: 10) {
                SignalButton(
                    caption: roundingCaption,
                    isActive: course.defaultRounding != nil,
                    activeColor: course.defaultRounding == .port ? .red : .green,
                    cloth: { RoundingFlagCloth(rounding: course.defaultRounding) },
                    action: {
                        withAnimation(CourseMotion.rounding) { course.cycleDefaultRounding() }
                    }
                )

                SignalButton(
                    caption: "Twice around",
                    isActive: course.twiceAround,
                    activeColor: Color(red: 0.114, green: 0.310, blue: 0.612),
                    cloth: { CodeFlagT(flying: course.twiceAround) },
                    action: {
                        withAnimation(CourseMotion.rounding) { course.toggleTwiceAround() }
                    }
                )
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("RC signals")
        } footer: {
            Text(signalsFooter)
        }
    }

    private var roundingCaption: String {
        switch course.defaultRounding {
        case .starboard: return "Green — stbd"
        case .port: return "Red — port"
        case nil: return "No flag"
        }
    }

    private var signalsFooter: String {
        let rounding = course.defaultRounding == nil
            ? "No course-wide rounding signalled — set each mark individually below."
            : "All marks \(roundingWord(course.defaultRounding)) unless a mark says otherwise."
        return course.twiceAround
            ? rounding + " Code flag T is up — the course is sailed twice."
            : rounding
    }

    private var courseSection: some View {
        Section {
            if course.course.isEmpty {
                ContentUnavailableView("No marks yet", systemImage: "point.topleft.down.curvedto.point.bottomright.up", description: Text("Tap a mark below to add it to the course."))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(course.course.enumerated()), id: \.element.uid) { index, entry in
                    CourseEntryRow(
                        entry: entry,
                        index: index,
                        isStart: course.isStartEntry(entry, index: index),
                        effectiveRounding: course.effectiveRounding(entry),
                        needsPosition: resolvedPosition(entry) == nil,
                        isInherited: entry.rounding == nil,
                        onCycleRounding: {
                            withAnimation(CourseMotion.rounding) {
                                course.cycleEntryRounding(uid: entry.uid)
                            }
                        }
                    )
                    // A mark slides in from the palette below and lifts back
                    // out the way it came, rather than the default fade that
                    // made the list look like it was redrawing itself.
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation(CourseMotion.remove) {
                                course.removeMark(uid: entry.uid)
                            }
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            placingEntry = entry
                        } label: {
                            Label("Place", systemImage: "mappin.and.ellipse")
                        }
                        .tint(.orange)
                        Button {
                            withAnimation(CourseMotion.start) {
                                course.startUid = entry.uid
                            }
                            course.persist()
                        } label: {
                            Label("Start", systemImage: "flag.checkered")
                        }
                        .tint(.green)
                    }
                }
                .onMove { from, to in
                    withAnimation(CourseMotion.reorder) {
                        course.moveMark(fromOffsets: from, toOffset: to)
                    }
                }
            }
        } header: {
            Text("Course")
        } footer: {
            Text("Tap a mark's S/P tag to set how it's rounded. A hollow tag means it's following the RC's signal above. Swipe left to place or set as start; swipe right to remove.")
        }
    }

    private var paletteSection: some View {
        Section("Marks — \(markListName)") {
            if isLoadingMarks {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if course.activeMarks.isEmpty {
                Text("No marks in this list.").foregroundStyle(.secondary)
            } else {
                ForEach(course.activeMarks) { mark in
                    Button {
                        // `_ =` matters: addMark is @discardableResult but
                        // still returns Bool, so without it this single-
                        // expression closure infers a Bool return that
                        // withAnimation cannot reconcile with the Button
                        // action's Void.
                        withAnimation(CourseMotion.add) {
                            _ = course.addMark(mark)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            MarkBadge(code: mark.code, govtLight: mark.govtLight, portable: mark.portable, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                // Lead with the code. Several real marks in
                                // these lists share a name - MBSA list A has
                                // two "Boston Approach Buoy" (J and L), list
                                // C has three "Weymouth Fore River Channel
                                // Buoy" - so a name-first row reads as
                                // duplicated entries when it is actually
                                // listing different buoys. The code is what
                                // tells them apart, and it is also what the
                                // RC posts on the board.
                                HStack(spacing: 6) {
                                    Text(mark.code)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(mark.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if mark.lat == nil || mark.lon == nil {
                                    Text("Portable — no charted position").font(.caption2).foregroundStyle(.orange)
                                } else if let light = mark.govtLight, !light.isEmpty {
                                    Text(light).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var summaryBar: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(course.legComputation.legs.count) legs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text(String(format: "%.2f nm total", course.legComputation.totalNm))
                        .font(.headline)
                        .monospacedDigit()
                        // Digits roll rather than cross-fade as marks are
                        // added, so the total reads as the same number
                        // changing instead of a new label appearing.
                        .contentTransition(.numericText())
                }
                Spacer()
                Button {
                    if course.setCourse() {
                        // Committed — navigate to Race tab's map.
                        onPlotCourse?()
                    }
                } label: {
                    Label("Plot Course", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Data loading

    /// The *list* name, not the club's - the club is shown separately in the
    /// race section, and a title reading "Boston Yacht Club" told the sailor
    /// nothing about which of that club's lists was loaded.
    private var markListName: String {
        course.rcListName ?? bootstrapListName ?? "Course Builder"
    }

    /// Prefers whatever list the store actually has loaded. Falling back to
    /// the bootstrap default unconditionally meant that after switching to
    /// another club's list, the title still named the old one.
    private var activeMarkListId: UUID? {
        course.activeMarkListId ?? appState.bootstrap?.selectedMarkListId
    }

    private func loadInitialMarksIfNeeded() async {
        guard course.activeMarks.isEmpty, let bootstrap = appState.bootstrap else { return }
        course.setActiveMarks(bootstrap.marks)
        course.setMarkListId(bootstrap.selectedMarkListId)
        course.restoreFor(markListId: bootstrap.selectedMarkListId)
    }

    /// Pull to refresh: re-fetches the loaded list's marks past the cache, so
    /// a mark a club admin moved in the web console shows up here.
    private func reloadMarks() async {
        guard let id = activeMarkListId else {
            await appState.hardRefresh()
            return
        }
        let list = appState.bootstrap?.markLists.first { $0.id == id }
            ?? MarkList(id: id, name: markListName, slug: "", scope: .club, ownerClubId: nil, sourceLabel: nil)
        await load(list: list, forceRefresh: true)
    }

    private func load(list: MarkList, forceRefresh: Bool) async {
        isLoadingMarks = true
        errorMessage = nil
        defer { isLoadingMarks = false }
        do {
            let marks = try await appState.selectMarkList(list, forceRefresh: forceRefresh)
            // Refreshing the list we already have must not wipe the course
            // the sailor is mid-way through building.
            let sameList = course.activeMarkListId == list.id
            course.setActiveMarks(marks, keepCourse: sameList)
            course.setMarkListId(list.id)
            if !sameList { course.restoreFor(markListId: list.id) }
        } catch APIError.server(status: 404, _) {
            // The list was deleted in the admin console while this phone
            // still had it selected. Say so and drop back to the home club's
            // default rather than leaving a dead list named in the header
            // with no marks under it.
            course.clearRCClub()
            // Clear the palette (and with it a course built from marks that
            // no longer exist) so the reload below repopulates from whatever
            // the club actually has now.
            course.setActiveMarks([])
            course.setMarkListId(nil)
            errorMessage = "That mark list was removed by the club. Pick another one."
            await appState.refresh()
            await loadInitialMarksIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CourseEntryRow: View {
    let entry: CourseEntry
    let index: Int
    let isStart: Bool
    let effectiveRounding: Rounding?
    let needsPosition: Bool
    /// True when this mark carries no rounding of its own and is following
    /// the RC's course-wide signal.
    let isInherited: Bool
    let onCycleRounding: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18)

            MarkBadge(
                code: entry.mark.code,
                govtLight: entry.mark.govtLight,
                portable: entry.mark.portable,
                rounding: effectiveRounding,
                isStart: isStart,
                size: 34
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.mark.name).font(.body.weight(.medium))
                    if isStart {
                        Text("START").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    if let effectiveRounding {
                        Text(roundingWord(effectiveRounding).capitalized)
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No rounding set").font(.caption).foregroundStyle(.secondary)
                    }
                    if needsPosition {
                        Label("Needs position", systemImage: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 6)

            // Its own control rather than a tap anywhere on the row: the old
            // behaviour was invisible, and it also meant every attempt to
            // select the row changed the course.
            Button(action: onCycleRounding) {
                RoundingTag(rounding: effectiveRounding, isInherited: isInherited)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rounding for \(entry.mark.code)")
            .accessibilityValue(effectiveRounding.map { roundingWord($0) } ?? "not set")
            .accessibilityHint("Cycles starboard, port, or follow the RC signal")
        }
        .padding(.vertical, 4)
    }
}

private struct VariationSheet: View {
    @State var variationDeg: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $variationDeg, in: -30...30, step: 0.1) {
                        Text("\(variationDeg, specifier: "%.1f")°")
                            .font(.title2.monospacedDigit())
                    }
                } header: {
                    Text("Magnetic variation")
                } footer: {
                    Text("Positive is easterly, negative is westerly. Applied to every true heading shown as magnetic.")
                }
            }
            .navigationTitle("Variation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(variationDeg); dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}
