//
//  RPSLiveActivityLiveActivity.swift
//  RPSLiveActivity
//
//  The Lock Screen card and Dynamic Island for an armed start sequence /
//  in-progress race: the countdown (rendered natively by the system from
//  `startAt`, so it keeps ticking without the app pushing an update every
//  second), which flag the RC should be flying, and - once available -
//  the current leg, distance, bearing, and wind. Started, updated, and
//  ended from the main app's `RaceLiveActivityManager`.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RPSLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaceActivityAttributes.self) { context in
            LockScreenRaceView(context: context)
                .activityBackgroundTint(Color(red: 0.04, green: 0.10, blue: 0.20))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.flag, systemImage: "flag.checkered")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(context.state)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    expandedDetail(context.state)
                }
            } compactLeading: {
                Image(systemName: "flag.checkered")
            } compactTrailing: {
                countdownText(context.state)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "flag.checkered")
            }
            .keylineTint(.cyan)
        }
    }
}

private struct LockScreenRaceView: View {
    let context: ActivityViewContext<RaceActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(context.attributes.clubName, systemImage: "flag.2.crossed.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(context.state.flag)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }

            HStack(alignment: .firstTextBaseline) {
                countdownText(context.state)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if let legLabel = context.state.legLabel {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(legLabel)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let dist = context.state.distNm {
                            Text(String(format: "%.2f nm", dist))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
            }

            if context.state.windFromDeg != nil || context.state.bearingTrue != nil {
                Divider().overlay(.white.opacity(0.2))
                expandedDetail(context.state)
            }
        }
        .padding(16)
    }
}

@ViewBuilder
private func countdownText(_ state: RaceActivityAttributes.ContentState) -> some View {
    if let startAt = state.startAt {
        Text(startAt, style: .timer)
    } else {
        Text("—:—")
    }
}

@ViewBuilder
private func expandedDetail(_ state: RaceActivityAttributes.ContentState) -> some View {
    HStack(spacing: 14) {
        if let legLabel = state.legLabel {
            Label(legLabel, systemImage: "arrow.triangle.turn.up.right.diamond")
        }
        if let bearing = state.bearingTrue {
            Label(String(format: "%03.0f°T", bearing), systemImage: "location.north.fill")
        }
        if let windFrom = state.windFromDeg, let windSpeed = state.windSpeedKts {
            Label(String(format: "%.0f kt", windSpeed) + " " + compassPoint(windFrom), systemImage: "wind")
        }
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(.white.opacity(0.9))
    .lineLimit(1)
}

/// A small local copy of the app's compass-point mapping - this file is
/// shared between the main app and this widget extension already (for
/// `RaceActivityAttributes`), and pulling in `SailingMath` too would mean
/// adding a second, unrelated file's target membership just for this.
private func compassPoint(_ deg: Double) -> String {
    let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    let normalized = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    let idx = Int((normalized / 22.5).rounded()) % 16
    return names[idx]
}

extension RaceActivityAttributes {
    fileprivate static var preview: RaceActivityAttributes {
        RaceActivityAttributes(clubName: "Boston YC")
    }
}

extension RaceActivityAttributes.ContentState {
    fileprivate static var warning: RaceActivityAttributes.ContentState {
        RaceActivityAttributes.ContentState(
            startAt: Date().addingTimeInterval(180),
            flag: "P flag up",
            isRacing: false,
            legLabel: nil,
            distNm: nil,
            bearingTrue: nil,
            windFromDeg: nil,
            windSpeedKts: nil
        )
    }

    fileprivate static var racing: RaceActivityAttributes.ContentState {
        RaceActivityAttributes.ContentState(
            startAt: Date().addingTimeInterval(-320),
            flag: "Started",
            isRacing: true,
            legLabel: "W1 → L1",
            distNm: 0.84,
            bearingTrue: 214,
            windFromDeg: 230,
            windSpeedKts: 12
        )
    }
}

#Preview("Notification", as: .content, using: RaceActivityAttributes.preview) {
    RPSLiveActivityLiveActivity()
} contentStates: {
    RaceActivityAttributes.ContentState.warning
    RaceActivityAttributes.ContentState.racing
}
