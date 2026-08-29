//
//  AppTabView.swift
//  RPS
//
//  The signed-in app: Course Builder, Race Mode, Weather, and Profile. Shows
//  the on-the-water disclaimer once per install before the sailor can dig
//  in.
//

import SwiftUI

enum AppTab: Int, Hashable {
    case course = 0
    case race = 1
    case weather = 2
    case profile = 3
}

struct AppTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(LivePositionStore.self) private var liveStore
    @Environment(StartSequenceViewModel.self) private var sequence
    @Environment(RaceLiveActivityManager.self) private var liveActivity
    @AppStorage("rps.hasSeenDisclaimer") private var hasSeenDisclaimer = false
    @State private var showDisclaimer = false
    @State private var selectedTab: AppTab = .course
    @State private var raceSegment: RaceModeView.Segment = .countdown

    var body: some View {
        TabView(selection: $selectedTab) {
            CourseBuilderView(
                onPlotCourse: {
                    selectedTab = .race
                    raceSegment = .map
                }
            )
            .tabItem { Label("Course", systemImage: "map") }
            .tag(AppTab.course)

            RaceModeView(selectedSegment: $raceSegment)
                .tabItem { Label("Race", systemImage: "flag.checkered.2.crossed") }
                .tag(AppTab.race)

            WeatherView()
                .tabItem { Label("Weather", systemImage: "cloud.sun.fill") }
                .tag(AppTab.weather)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .onAppear {
            if !hasSeenDisclaimer { showDisclaimer = true }
        }
        // Ask for location as soon as the app is usable, not only when the
        // Race tab happens to be opened. The app launches on the Course tab,
        // where placing a portable mark from the current position is one of
        // the first things a sailor does - previously that silently had no
        // fix, and the permission prompt had never even been shown, because
        // nothing outside Race Mode ever started the receiver.
        .task {
            // Held back while the disclaimer is up so the system location
            // alert doesn't land on top of it.
            if hasSeenDisclaimer { liveStore.start(userInitiated: false) }
            // Clears out (or re-adopts) any Live Activity left over from a
            // previous session - see RaceLiveActivityManager.reconnect for
            // why this can't just be left for the next sync() call.
            liveActivity.reconnect(isSequenceRunning: sequence.running)
            // Covers a cold launch via the widget: .onOpenURL can fire
            // before AppTabView exists at all (the app starts on the
            // launch screen, not this view), so the link is already
            // sitting there by the time this .task runs - .onChange below
            // only catches one that arrives while this view is already on
            // screen, so both paths are needed.
            applyPendingDeepLink()
        }
        .sheet(isPresented: $showDisclaimer, onDismiss: {
            hasSeenDisclaimer = true
            liveStore.start(userInitiated: false)
        }) {
            DisclaimerView()
        }
        .onChange(of: appState.pendingDeepLink) { _, _ in applyPendingDeepLink() }
    }

    private func applyPendingDeepLink() {
        guard let link = appState.pendingDeepLink else { return }
        selectedTab = .race
        switch link {
        case .countdown: raceSegment = .countdown
        case .leg: raceSegment = .leg
        }
        // Consumed - clearing it means re-tapping the same widget target
        // re-fires this (a fresh URL open always re-sets it to a non-nil
        // value first), while nothing else in the app can trigger it
        // again by accident.
        appState.pendingDeepLink = nil
    }
}
