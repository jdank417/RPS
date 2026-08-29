//
//  RPSRaceWidget.swift
//  RPSLiveActivity
//
//  A Home Screen widget with two faces, switched on whether a race is
//  actually running: mid-race, it mirrors the current leg the same way
//  the Live Activity does (same shared data, in fact - see
//  WidgetSharedStore.loadRace in RaceActivityAttributes.swift); otherwise
//  it's a "Start Race" shortcut into the countdown screen with the
//  current wind alongside it, so there's still something worth glancing
//  at before a race has even begun.
//

import WidgetKit
import SwiftUI

struct RaceEntry: TimelineEntry {
    let date: Date
    let race: RaceActivityAttributes.ContentState?
    let wind: WindWidgetSnapshot?
}

struct RaceTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RaceEntry {
        RaceEntry(
            date: Date(),
            race: RaceActivityAttributes.ContentState(
                startAt: nil, flag: "Started", isRacing: true, legLabel: "W1 → L1",
                distNm: 0.84, bearingTrue: 214, windFromDeg: 230, windSpeedKts: 12
            ),
            wind: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (RaceEntry) -> Void) {
        completion(RaceEntry(date: Date(), race: WidgetSharedStore.loadRace(), wind: WidgetSharedStore.loadWind()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RaceEntry>) -> Void) {
        let entry = RaceEntry(date: Date(), race: WidgetSharedStore.loadRace(), wind: WidgetSharedStore.loadWind())
        // The app reloads this widget itself on every real change
        // (RaceLiveActivityManager.syncWidget) - this scheduled refresh is
        // only the fallback for whenever the app hasn't run in a while.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct RPSRaceWidgetEntryView: View {
    let entry: RaceEntry

    var body: some View {
        if let race = entry.race, race.isRacing || race.startAt != nil {
            legView(race)
                .widgetURL(URL(string: "rps://leg"))
        } else {
            idleView
                .widgetURL(URL(string: "rps://countdown"))
        }
    }

    // MARK: - Racing

    private func legView(_ race: RaceActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(race.flag.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let legLabel = race.legLabel {
                Text(legLabel)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if let startAt = race.startAt {
                Text(startAt, style: .timer)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            if let dist = race.distNm {
                Label(String(format: "%.2f nm", dist), systemImage: "ruler")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let bearing = race.bearingTrue {
                Label(String(format: "%03.0f°T", bearing), systemImage: "location.north.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let windFrom = race.windFromDeg, let windSpeed = race.windSpeedKts {
                Label(String(format: "%.0f kt", windSpeed) + " " + compassPoint(windFrom), systemImage: "wind")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Idle

    private var idleView: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.title2)
                Text("Start Race")
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Divider()

            if let wind = entry.wind {
                VStack(spacing: 4) {
                    Label("WIND", systemImage: "wind")
                        .font(.caption2.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f kt", wind.speedKts))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                            .rotationEffect(.degrees(wind.fromDeg + 180))
                        Text("\(compassPoint(wind.fromDeg))")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "wind")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No wind yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func compassPoint(_ deg: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalized = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let idx = Int((normalized / 22.5).rounded()) % 16
        return names[idx]
    }
}

struct RPSRaceWidget: Widget {
    let kind: String = "RPSRaceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RaceTimelineProvider()) { entry in
            RPSRaceWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Race")
        .description("The current leg while racing, or a quick start when you're not.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview(as: .systemMedium) {
    RPSRaceWidget()
} timeline: {
    RaceEntry(
        date: .now,
        race: RaceActivityAttributes.ContentState(
            startAt: nil, flag: "Started", isRacing: true, legLabel: "W1 → L1",
            distNm: 0.84, bearingTrue: 214, windFromDeg: 230, windSpeedKts: 12
        ),
        wind: nil
    )
    RaceEntry(date: .now, race: nil, wind: WindWidgetSnapshot(fromDeg: 230, speedKts: 12, gustKts: 16, at: Date()))
    RaceEntry(date: .now, race: nil, wind: nil)
}
