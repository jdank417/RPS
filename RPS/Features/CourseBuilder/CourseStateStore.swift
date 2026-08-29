//
//  CourseStateStore.swift
//  RPS
//
//  Owns the in-progress course: the ordered list of mark occurrences, their
//  roundings, the RC's course-wide signals (green flag / twice-around), the
//  start line, and the derived leg computation. Ported from the reference
//  app's `CourseStateService` as an `@Observable` store, persisted to
//  UserDefaults (mirroring its localStorage persistence) so a course
//  survives the app being backgrounded or relaunched mid-build.
//
//  Shared between the Course Builder (which edits it) and Race Mode (which
//  reads legs/positions from it), same as in the reference app.
//

import Foundation
import Observation
// `Array.move(fromOffsets:toOffset:)`, used by drag-to-reorder in the course
// builder's list, is a SwiftUI extension rather than a Foundation one.
import SwiftUI

@Observable
@MainActor
final class CourseStateStore {

    private struct Persisted: Codable {
        var course: [CourseEntry]
        var defaultRounding: Rounding?
        var twiceAround: Bool
        var startUid: Int?
        var committed: Bool
        var variationDeg: Double
        var markListId: UUID?
        var rcClubSlug: String?
        var rcClubName: String?
        var rcListName: String?
    }

    private static let cacheKey = "rps.cache.course"
    private var uidCounter = 0
    private var markListId: UUID?
    
    /// The RC club slug and name — persisted so the sailor knows which club's
    /// marks they're working with across app restarts. Not the same as the
    /// sailor's home club.
    var rcClubSlug: String?
    var rcClubName: String?
    var rcListName: String?

    var activeMarks: [Mark] = []
    var course: [CourseEntry] = []
    /// Starts at port rather than unset. Leaving every mark with no rounding
    /// meant the common case needed a tap before the course meant anything,
    /// and port is the usual signal - the RC still flies a green flag when
    /// it isn't, and the signals row is one tap away.
    var defaultRounding: Rounding? = .port
    var twiceAround = false
    var startUid: Int?
    /// Which unplaced entry a GPS/manual fix should apply to next. Nil means
    /// "the start", the default target.
    var positionTargetUid: Int?
    var committed = false
    var variationDeg: Double
    var statusMessage: String?
    var statusIsError = false
    /// The leg currently shown in the navigator / highlighted on the map.
    var currentLegIndexRaw = 0

    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.variationDeg = settings.variationDeg
        restoreSaved()
    }

    var unplaced: [CourseEntry] { unplacedEntries(course) }

    /// Everything `computeCourseLegs` reads. Snapshotted so the memoised
    /// result below can tell "nothing that matters changed" from "recompute".
    private struct ComputationInputs: Equatable {
        var course: [CourseEntry]
        var defaultRounding: Rounding?
        var twiceAround: Bool
        var startUid: Int?
        var variationDeg: Double
    }

    // Deliberately not observed: these are a cache of a value derived from
    // observed state, not state in their own right. Observing them would
    // re-invalidate every view that reads `legComputation` the moment the
    // cache filled, which is the loop this exists to avoid.
    @ObservationIgnored private var cachedInputs: ComputationInputs?
    @ObservationIgnored private var cachedComputation: CourseComputation?

    /// The course's legs, distances and map points.
    ///
    /// Memoised because this is read several times per SwiftUI body pass (the
    /// map alone reads `.mapPoints`, `.legs.isEmpty`, the current leg and the
    /// leg count) and those bodies re-evaluate on every GPS fix - roughly once
    /// a second while racing. Recomputing a haversine and a bearing per leg,
    /// several times a second, for a course that has not changed is where the
    /// map's frame drops were coming from. The inputs comparison is a handful
    /// of cheap field compares over a course that is realistically under a
    /// dozen marks.
    var legComputation: CourseComputation {
        let inputs = ComputationInputs(
            course: course, defaultRounding: defaultRounding, twiceAround: twiceAround,
            startUid: startUid, variationDeg: variationDeg
        )
        if inputs == cachedInputs, let cachedComputation {
            return cachedComputation
        }
        let fresh = computeCourseLegs(course, opts: CourseLegOptions(
            defaultRounding: defaultRounding, twiceAround: twiceAround, startUid: startUid, variationDeg: variationDeg
        ))
        cachedInputs = inputs
        cachedComputation = fresh
        return fresh
    }

    /// Clamped to the current leg count so it never points past the end when
    /// the course shrinks (a mark removed, twice-around toggled off, etc).
    var currentLegIndex: Int? {
        let count = legComputation.legs.count
        guard count > 0 else { return nil }
        return max(0, min(currentLegIndexRaw, count - 1))
    }

    func setCurrentLeg(_ idx: Int) {
        currentLegIndexRaw = idx
    }

    // MARK: - Persistence

    func persist() {
        let snapshot = Persisted(
            course: course, defaultRounding: defaultRounding, twiceAround: twiceAround,
            startUid: startUid, committed: committed, variationDeg: variationDeg, markListId: markListId,
            rcClubSlug: rcClubSlug, rcClubName: rcClubName, rcListName: rcListName
        )
        guard !snapshot.course.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.cacheKey)
            return
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    /// Restores a saved course, but only if it belongs to the list now
    /// loaded — otherwise its mark codes would refer to a different club's
    /// buoys.
    @discardableResult
    func restoreFor(markListId: UUID?) -> Bool {
        self.markListId = markListId
        guard let saved = readCache(), saved.markListId == markListId else { return false }
        return apply(saved)
    }

    private func restoreSaved() {
        guard let saved = readCache() else { return }
        if apply(saved) { markListId = saved.markListId }
    }

    private func readCache() -> Persisted? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(Persisted.self, from: data)
    }

    @discardableResult
    private func apply(_ s: Persisted) -> Bool {
        guard !s.course.isEmpty else { return false }
        course = s.course
        defaultRounding = s.defaultRounding
        twiceAround = s.twiceAround
        startUid = s.startUid
        committed = s.committed
        variationDeg = s.variationDeg
        rcClubSlug = s.rcClubSlug
        rcClubName = s.rcClubName
        rcListName = s.rcListName
        uidCounter = s.course.map(\.uid).max() ?? 0
        return true
    }

    /// Which mark list the palette is currently loaded from. Set either by
    /// the bootstrap default or by an explicit RC-club/list choice.
    var activeMarkListId: UUID? { markListId }

    func setMarkListId(_ id: UUID?) {
        markListId = id
    }
    
    func setRCClub(slug: String, name: String, listName: String?) {
        rcClubSlug = slug
        rcClubName = name
        rcListName = listName
        persist()
    }

    func clearRCClub() {
        rcClubSlug = nil
        rcClubName = nil
        rcListName = nil
        persist()
    }

    // MARK: - List switching

    /// Swaps the palette to a new set of marks. By default this also clears
    /// the course, because marks from a different list aren't meaningful in
    /// this one. Pass `keepCourse` when the marks are a refresh of the same
    /// list.
    func setActiveMarks(_ marks: [Mark], keepCourse: Bool = false) {
        activeMarks = marks
        guard keepCourse else {
            resetCourse()
            return
        }
        let byCode = Dictionary(uniqueKeysWithValues: marks.map { ($0.code, $0) })
        course = course.map { entry in
            guard let fresh = byCode[entry.mark.code] else { return entry }
            var updated = entry
            updated.mark = fresh
            return updated
        }
    }

    func resetCourse() {
        course = []
        committed = false
        startUid = nil
        positionTargetUid = nil
        setStatus(nil)
    }

    // MARK: - Building

    func lastCourseMark() -> Mark? { course.last?.mark }

    /// Rounding the same mark twice in a row isn't a real course, and it
    /// makes a zero-length leg — reject it rather than silently accepting it.
    func isRepeatOfLast(_ mark: Mark) -> Bool {
        lastCourseMark()?.code == mark.code
    }

    @discardableResult
    func addMark(_ mark: Mark) -> Bool {
        if isRepeatOfLast(mark) {
            setStatus("\(mark.code) is already the last mark.", isError: true)
            return false
        }
        uidCounter += 1
        course.append(CourseEntry(uid: uidCounter, mark: mark, overrideLat: nil, overrideLon: nil, rounding: nil))
        setStatus(nil)
        return true
    }

    func removeMark(uid: Int) {
        course.removeAll { $0.uid == uid }
        if positionTargetUid == uid { positionTargetUid = nil }
        if startUid == uid { startUid = nil }
    }

    func moveMark(fromOffsets: IndexSet, toOffset: Int) {
        course.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    // MARK: - Rounding

    func effectiveRounding(_ entry: CourseEntry) -> Rounding? {
        entry.rounding ?? defaultRounding
    }

    func cycleEntryRounding(uid: Int) {
        guard let idx = course.firstIndex(where: { $0.uid == uid }) else { return }
        course[idx].rounding = cycleRounding(course[idx].rounding)
    }

    func cycleDefaultRounding() {
        defaultRounding = cycleRounding(defaultRounding)
    }

    func toggleTwiceAround() {
        twiceAround.toggle()
    }

    func setVariationDeg(_ deg: Double) {
        variationDeg = deg
        settings.variationDeg = deg
    }

    // MARK: - Start / position placement

    func isStartEntry(_ entry: CourseEntry, index: Int) -> Bool {
        RPS.isStartEntry(entry, index: index, startUid: startUid)
    }

    /// The course's current start entry, by the same rule the leg
    /// computation uses: whichever entry `startUid` names, or — before one
    /// is chosen — a leading mark whose own name says "start".
    var startEntry: CourseEntry? {
        for (index, entry) in course.enumerated() where isStartEntry(entry, index: index) {
            return entry
        }
        return nil
    }

    /// True once the start is tied to a charted (non-portable) mark with a
    /// known position, set via `setStartFromMark`. A charted mark's
    /// position is on the chart already — Race Mode should only need the
    /// committee boat pinged, never the pin end too.
    var startIsChartedMark: Bool {
        guard let entry = startEntry else { return false }
        return !entry.mark.portable && entry.mark.lat != nil && entry.mark.lon != nil
    }

    func choosePositionTarget(uid: Int) {
        positionTargetUid = positionTargetUid == uid ? nil : uid
        if let uid = positionTargetUid, let target = course.first(where: { $0.uid == uid }) {
            setStatus("Placing \(target.mark.code) — enter a position for it below.")
        } else {
            setStatus(nil)
        }
    }

    /// Which course entry a start position should attach to. Only ever a
    /// mark that has no charted position of its own — an RC-set pin, or a
    /// leading portable/unresolved mark. A charted mark is never a
    /// candidate: overwriting its position would silently move a real buoy.
    func findStartTargetEntry() -> CourseEntry? {
        if let pin = course.first(where: { $0.mark.portable && resolvedPosition($0) == nil }) {
            return pin
        }
        if let first = course.first, first.mark.portable || resolvedPosition(first) == nil {
            return first
        }
        return nil
    }

    /// Gives the start position something to attach to, inserting a
    /// synthetic start entry at the front of the course when there isn't
    /// already a suitable one. Prefers the list's own portable start mark,
    /// when it has one, so the course reads the way the club writes it.
    @discardableResult
    func ensureStartEntry() -> CourseEntry {
        if let existing = findStartTargetEntry() { return existing }

        let ownStart = activeMarks.first { $0.portable && $0.name.range(of: "start", options: .caseInsensitive) != nil }
        let startMark = ownStart ?? Mark.syntheticStart()
        uidCounter += 1
        let entry = CourseEntry(uid: uidCounter, mark: startMark, overrideLat: nil, overrideLon: nil, rounding: nil)
        course.insert(entry, at: 0)
        return entry
    }

    /// Applies a GPS/manual fix as a position. If a specific entry was chosen
    /// via `choosePositionTarget`, the fix goes there; otherwise it becomes
    /// the start. The fix is applied to every course entry sharing the
    /// target's mark code, since start/finish is often the same physical
    /// mark used twice.
    @discardableResult
    func applyPosition(lat: Double, lon: Double, sourceLabel: String) -> (targetLabel: String, count: Int) {
        let chosen = positionTargetUid.flatMap { uid in course.first(where: { $0.uid == uid }) }
        let target = chosen ?? ensureStartEntry()
        if chosen == nil { startUid = target.uid }
        positionTargetUid = nil

        let targetCode = target.mark.code
        var count = 0
        course = course.map { entry in
            guard entry.mark.code == targetCode else { return entry }
            count += 1
            var updated = entry
            updated.overrideLat = lat
            updated.overrideLon = lon
            return updated
        }
        setStatus(
            (chosen != nil ? "Placed " : "Start ") + target.mark.code + " from " + sourceLabel
                + (count > 1 ? " — applied to \(count) marks." : ".")
        )
        return (target.mark.code, count)
    }

    /// Sets the start at a charted (non-portable) mark. Returns false (with a
    /// status message) if the mark has no charted position.
    @discardableResult
    func setStartFromMark(_ mark: Mark) -> Bool {
        guard mark.lat != nil, mark.lon != nil else {
            setStatus("\(mark.code) has no charted position — pick a fixed mark, or enter a position instead.", isError: true)
            return false
        }

        let existing = positionTargetUid.flatMap { uid in course.first(where: { $0.uid == uid }) } ?? findStartTargetEntry()

        let entryUid: Int
        if let existing {
            if let idx = course.firstIndex(where: { $0.uid == existing.uid }) {
                course[idx].mark = mark
                course[idx].overrideLat = nil
                course[idx].overrideLon = nil
            }
            entryUid = existing.uid
        } else if let first = course.first, first.mark.code == mark.code {
            entryUid = first.uid
        } else {
            uidCounter += 1
            let entry = CourseEntry(uid: uidCounter, mark: mark, overrideLat: nil, overrideLon: nil, rounding: nil)
            course.insert(entry, at: 0)
            entryUid = entry.uid
        }

        startUid = entryUid
        positionTargetUid = nil
        setStatus("Start set at \(mark.code) — \(mark.name).")
        return true
    }

    /// Marks the start as something to be pinged live on the water, rather
    /// than tied to a charted mark. Reuses the current start entry when
    /// there is one — swapping a charted mark back out for a placeholder —
    /// so switching the choice never leaves an orphaned entry behind.
    func setStartToPing() {
        let ownStart = activeMarks.first { $0.portable && $0.name.range(of: "start", options: .caseInsensitive) != nil }

        if let entry = startEntry, !entry.mark.portable, let idx = course.firstIndex(where: { $0.uid == entry.uid }) {
            course[idx].mark = ownStart ?? Mark.syntheticStart()
            course[idx].overrideLat = nil
            course[idx].overrideLon = nil
            startUid = course[idx].uid
        } else {
            startUid = ensureStartEntry().uid
        }
        setStatus("Start will be pinged live — use \"Ping Pin\" in Race Mode.")
    }

    // MARK: - Commit

    /// Commits the course for plotting. Returns false (with a status
    /// message) if there are fewer than two marks or any mark still lacks a
    /// position.
    @discardableResult
    func setCourse() -> Bool {
        guard course.count >= 2 else {
            setStatus("Add at least two marks to plot a course.", isError: true)
            return false
        }
        guard unplaced.isEmpty else {
            reportUnplaced()
            return false
        }
        committed = true
        setStatus(nil)
        return true
    }

    func reportUnplaced() {
        let names = Array(Set(unplaced.map { $0.mark.code })).sorted().joined(separator: ", ")
        setStatus("Set a position for \(names) before plotting.", isError: true)
    }

    func setStatus(_ message: String?, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError
    }
}
