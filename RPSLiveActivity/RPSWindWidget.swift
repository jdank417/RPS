//
//  RPSWindWidget.swift
//  RPSLiveActivity
//
//  A Home Screen widget for the one thing worth a glance before you've
//  even opened the app: what the wind's doing. Reads whatever the main
//  app's WindService last wrote to the shared App Group container (see
//  WidgetSharedStore in RaceActivityAttributes.swift) - a plain WidgetKit
//  widget's TimelineProvider runs in this extension's own process on the
//  system's own schedule, so unlike the Live Activity there's no way for
//  the app to push it a value directly.
//

import WidgetKit
import SwiftUI

struct WindEntry: TimelineEntry {
    let date: Date
    let snapshot: WindWidgetSnapshot?
}

struct WindTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WindEntry {
        WindEntry(date: Date(), snapshot: WindWidgetSnapshot(fromDeg: 230, speedKts: 12, gustKts: 15, at: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (WindEntry) -> Void) {
        completion(WindEntry(date: Date(), snapshot: WidgetSharedStore.loadWind()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WindEntry>) -> Void) {
        let entry = WindEntry(date: Date(), snapshot: WidgetSharedStore.loadWind())
        // The app reloads this widget's timeline itself the moment it gets
        // a fresh reading (WindService.apply -> WidgetCenter.reloadTimelines),
        // so this scheduled refresh is only the fallback for whenever the
        // app hasn't been opened in a while - matching WindService's own
        // "worth a re-fetch" interval rather than anything tighter.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct RPSWindWidgetEntryView: View {
    let entry: WindEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            windView(snapshot)
        } else {
            emptyView
        }
    }

    private func windView(_ snapshot: WindWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("WIND", systemImage: "wind")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.0f", snapshot.speedKts))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("kt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                    .rotationEffect(.degrees(snapshot.fromDeg + 180))
                Text("\(compassPoint(snapshot.fromDeg)) · \(Int(snapshot.fromDeg.rounded()))°T")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.secondary)

            if family == .systemMedium, let gust = snapshot.gustKts {
                Text(String(format: "Gusts %.0f kt", gust))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            Text(ageText(snapshot.at))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "wind")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open RPS for wind")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func ageText(_ date: Date) -> String {
        let mins = Int(Date().timeIntervalSince(date) / 60)
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins) min ago" }
        return "\(mins / 60)h ago"
    }

    private func compassPoint(_ deg: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalized = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let idx = Int((normalized / 22.5).rounded()) % 16
        return names[idx]
    }
}

struct RPSWindWidget: Widget {
    let kind: String = "RPSWindWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WindTimelineProvider()) { entry in
            RPSWindWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Wind")
        .description("Current wind speed and direction from RPS.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    RPSWindWidget()
} timeline: {
    WindEntry(date: .now, snapshot: WindWidgetSnapshot(fromDeg: 230, speedKts: 12, gustKts: 16, at: Date().addingTimeInterval(-300)))
    WindEntry(date: .now, snapshot: nil)
}
