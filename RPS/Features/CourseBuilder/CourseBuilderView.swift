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

    var onPlotCourse: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                raceSection

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
            .onChange(of: course.course) { _, _ in course.persist() }
            .onChange(of: course.twiceAround) { _, _ in course.persist() }
            .onChange(of: course.startUid) { _, _ in course.persist() }
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
                        needsPosition: resolvedPosition(entry) == nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { course.cycleEntryRounding(uid: entry.uid) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            course.removeMark(uid: entry.uid)
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
                            course.startUid = entry.uid
                        } label: {
                            Label("Start", systemImage: "flag.checkered")
                        }
                        .tint(.green)
                    }
                }
                .onMove { course.moveMark(fromOffsets: $0, toOffset: $1) }
            }
        } header: {
            Text("Course")
        } footer: {
            Text("Tap a mark to cycle its rounding (S → P → default). Swipe left to place or set as start; swipe right to remove.")
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
                        course.addMark(mark)
                    } label: {
                        HStack(spacing: 12) {
                            MarkBadge(code: mark.code, govtLight: mark.govtLight, portable: mark.portable, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mark.name).foregroundStyle(.primary)
                                if mark.lat == nil || mark.lon == nil {
                                    Text("Portable — no charted position").font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                        }
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
                    Text("\(course.legComputation.legs.count) legs").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.2f nm total", course.legComputation.totalNm))
                        .font(.headline)
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
            Spacer()
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
