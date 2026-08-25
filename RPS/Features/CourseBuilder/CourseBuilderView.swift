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
    @State private var switchingListId: UUID?

    var onPlotCourse: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle(markListName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showRCClubPicker = true
                    } label: {
                        Label("RC Club", systemImage: "flag.2.crossed")
                    }
                    Button {
                        showMarkListPicker = true
                    } label: {
                        Label("Mark Lists", systemImage: "list.bullet.rectangle")
                    }
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
            .sheet(isPresented: $showMarkListPicker) {
                MarkListPickerSheet(
                    markLists: appState.bootstrap?.markLists ?? [],
                    selectedId: activeMarkListId
                ) { list in
                    Task { await switchList(to: list) }
                }
            }
            .sheet(isPresented: $showRCClubPicker) {
                RCClubPickerSheet { club, list, marks in
                    course.setRCClub(slug: club.slug, name: club.name)
                    course.setActiveMarks(marks)
                    course.setMarkListId(list.id)
                    course.restoreFor(markListId: list.id)
                }
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

    // MARK: - Sections

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

    private var markListName: String {
        if let rcName = course.rcClubName {
            return rcName
        }
        return appState.bootstrap?.markLists.first { $0.id == activeMarkListId }?.name ?? "Course Builder"
    }

    private var activeMarkListId: UUID? {
        appState.bootstrap?.selectedMarkListId
    }

    private func loadInitialMarksIfNeeded() async {
        guard course.activeMarks.isEmpty, let bootstrap = appState.bootstrap else { return }
        course.setActiveMarks(bootstrap.marks)
        course.restoreFor(markListId: bootstrap.selectedMarkListId)
    }

    private func switchList(to list: MarkList) async {
        switchingListId = list.id
        isLoadingMarks = true
        errorMessage = nil
        defer { isLoadingMarks = false; switchingListId = nil }
        do {
            let marks = try await appState.selectMarkList(list)
            course.setActiveMarks(marks)
            course.setMarkListId(list.id)
            course.restoreFor(markListId: list.id)
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
