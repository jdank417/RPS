//
//  AppTabView.swift
//  RPS
//
//  The signed-in app: Course Builder, Race Mode, and Profile. Shows the
//  on-the-water disclaimer once per install before the sailor can dig in.
//

import SwiftUI

struct AppTabView: View {
    @AppStorage("rps.hasSeenDisclaimer") private var hasSeenDisclaimer = false
    @State private var showDisclaimer = false

    var body: some View {
        TabView {
            CourseBuilderView()
                .tabItem { Label("Course", systemImage: "map") }

            RaceModeView()
                .tabItem { Label("Race", systemImage: "flag.checkered.2.crossed") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .onAppear {
            if !hasSeenDisclaimer { showDisclaimer = true }
        }
        .sheet(isPresented: $showDisclaimer, onDismiss: { hasSeenDisclaimer = true }) {
            DisclaimerView()
        }
    }
}
