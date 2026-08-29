//
//  RPSApp.swift
//  RPS
//
//  Created by Jason Dank on 8/25/26.
//
//  Wires up the app's shared, long-lived @Observable stores once here and
//  hands them down via the environment, so Course Builder and Race Mode
//  read and write the same course/GPS/wind state rather than each holding
//  their own copy.
//

import SwiftUI

@main
struct RPSApp: App {

    @State private var appState: AppState
    @State private var settings: AppSettings
    @State private var courseStore: CourseStateStore
    @State private var liveStore: LivePositionStore
    @State private var windService: WindService
    @State private var tidalCurrentService: TidalCurrentService
    @State private var sequenceViewModel: StartSequenceViewModel
    @State private var raceViewModel: RaceViewModel
    @State private var liveActivityManager: RaceLiveActivityManager

    init() {
        let settings = AppSettings.shared
        let courseStore = CourseStateStore(settings: settings)
        let liveStore = LivePositionStore()
        let windService = WindService()

        _appState = State(initialValue: AppState())
        _settings = State(initialValue: settings)
        _courseStore = State(initialValue: courseStore)
        _liveStore = State(initialValue: liveStore)
        _windService = State(initialValue: windService)
        _tidalCurrentService = State(initialValue: TidalCurrentService())
        _sequenceViewModel = State(initialValue: StartSequenceViewModel())
        _raceViewModel = State(initialValue: RaceViewModel(courseStore: courseStore, liveStore: liveStore, windService: windService))
        _liveActivityManager = State(initialValue: RaceLiveActivityManager())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(settings)
                .environment(courseStore)
                .environment(liveStore)
                .environment(windService)
                .environment(tidalCurrentService)
                .environment(sequenceViewModel)
                .environment(raceViewModel)
                .environment(liveActivityManager)
                // RPSRaceWidget's tap targets - rps://countdown, rps://leg.
                // Requires the "rps" URL scheme registered under the RPS
                // target's Info -> URL Types in Xcode.
                .onOpenURL { url in appState.handle(url: url) }
        }
    }
}
