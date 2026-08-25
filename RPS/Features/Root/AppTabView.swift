//
//  AppTabView.swift
//  RPS
//
//  The signed-in app: Course Builder, Race Mode, and Profile. Shows the
//  on-the-water disclaimer once per install before the sailor can dig in.
//

import SwiftUI

enum AppTab: Int, Hashable {
    case course = 0
    case race = 1
    case profile = 2
}

struct AppTabView: View {
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

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .onAppear {
            if !hasSeenDisclaimer { showDisclaimer = true }
        }
        .sheet(isPresented: $showDisclaimer, onDismiss: { hasSeenDisclaimer = true }) {
            DisclaimerView()
        }
    }
}
