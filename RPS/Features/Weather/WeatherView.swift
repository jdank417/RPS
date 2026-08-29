//
//  WeatherView.swift
//  RPS
//
//  What WeatherKit adds beyond the plain forecast wind used mid-race:
//  current conditions, pressure and its trend, visibility, UV - and, the
//  reason this tab exists, an hourly wind trend so a crew can see whether
//  the breeze is building, dying, or shifting over the next few hours
//  rather than only knowing what it's doing right now.
//

import SwiftUI

struct WeatherView: View {
    @Environment(LivePositionStore.self) private var liveStore
    @Environment(CourseStateStore.self) private var course
    @State private var service = RaceWeatherService()

    /// The boat's live GPS fix when there is one; otherwise the first
    /// resolved position in the built course, so this tab is useful before
    /// GPS has a fix (indoors, at the dock) as long as a course exists.
    private var location: (lat: Double, lon: Double)? {
        if let fix = liveStore.fix { return (fix.lat, fix.lon) }
        if let point = course.legComputation.mapPoints.compactMap({ $0 }).first {
            return (point.lat, point.lon)
        }
        return nil
    }

    private var locationSourceText: String {
        liveStore.fix != nil ? "Your position" : "Course start"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let snapshot = service.snapshot {
                        currentCard(snapshot)
                        statsGrid(snapshot)
                        if !snapshot.hourly.isEmpty {
                            hourlyTrend(snapshot.hourly)
                        }
                    } else if service.isLoading {
                        ProgressView("Fetching weather…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if let error = service.error {
                        ContentUnavailableView {
                            Label("WeatherKit not available", systemImage: "cloud.slash")
                        } description: {
                            Text(error)
                        } actions: {
                            if location != nil {
                                Button("Try Again") { Task { await load(force: true) } }
                            }
                        }
                        .frame(minHeight: 300)
                    } else if location == nil {
                        ContentUnavailableView(
                            "No position yet",
                            systemImage: "location.slash",
                            description: Text("Start GPS or build a course to see weather here.")
                        )
                        .frame(minHeight: 300)
                    }

                    if let error = service.error, service.snapshot != nil {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .refreshable { await load(force: true) }
            .navigationTitle("Weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(service.isLoading || location == nil)
                }
            }
            .task { await load(force: false) }
            .onChange(of: liveStore.fix) { _, _ in Task { await load(force: false) } }
        }
    }

    private func load(force: Bool) async {
        guard let location else { return }
        await service.refresh(lat: location.lat, lon: location.lon, force: force)
    }

    // MARK: - Current conditions

    private func currentCard(_ snapshot: RaceWeatherSnapshot) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label(locationSourceText, systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(service.stale ? "Updated \(ageText(snapshot.observedAt)) · stale" : "Updated \(ageText(snapshot.observedAt))")
                    .font(.caption)
                    .foregroundStyle(service.stale ? Color.orange : Color.secondary)
            }

            HStack(spacing: 20) {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: 44))
                    .symbolRenderingMode(.multicolor)
                Text(snapshot.temperature.formatted())
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .rotationEffect(.degrees(snapshot.windFromDeg + 180))
                        Text(String(format: "%.0f kt", snapshot.windSpeed.value))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                    }
                    Text("\(SailingMath.compassPoint(snapshot.windFromDeg)) · \(Int(snapshot.windFromDeg.rounded()))°T")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let gust = snapshot.gust {
                        Text(String(format: "Gusts %.0f kt", gust.value))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func ageText(_ date: Date) -> String {
        let mins = Int((Date().timeIntervalSince(date) / 60).rounded())
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins) min ago" }
        let hrs = Int((Double(mins) / 60).rounded())
        return "\(hrs)h ago"
    }

    // MARK: - Stats

    private func statsGrid(_ snapshot: RaceWeatherSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            statTile(
                title: "PRESSURE",
                value: snapshot.pressure.formatted(),
                caption: snapshot.pressureTrend.label,
                captionSymbol: snapshot.pressureTrend.symbolName
            )
            statTile(title: "VISIBILITY", value: snapshot.visibility.formatted(), caption: nil, captionSymbol: nil)
            statTile(title: "HUMIDITY", value: "\(Int((snapshot.humidity * 100).rounded()))%", caption: nil, captionSymbol: nil)
            statTile(title: "UV INDEX", value: "\(snapshot.uvIndex)", caption: uvCaption(snapshot.uvIndex), captionSymbol: nil)
        }
    }

    private func uvCaption(_ index: Int) -> String {
        switch index {
        case 0...2: return "Low"
        case 3...5: return "Moderate"
        case 6...7: return "High"
        case 8...10: return "Very high"
        default: return "Extreme"
        }
    }

    private func statTile(title: String, value: String, caption: String?, captionSymbol: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            if let caption {
                if let captionSymbol {
                    Label(caption, systemImage: captionSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Hourly trend

    /// The reason this tab exists: is the breeze building, dying, or
    /// shifting over the next few hours - not just what it's doing now.
    private func hourlyTrend(_ hours: [HourlyWindPoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WIND TREND")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(hours) { hour in
                        VStack(spacing: 6) {
                            Text(hour.date.formatted(.dateTime.hour()))
                                .font(.caption.weight(.semibold))
                            Image(systemName: hour.symbolName)
                                .font(.subheadline)
                                .symbolRenderingMode(.multicolor)
                            Image(systemName: "arrow.up")
                                .font(.caption)
                                .rotationEffect(.degrees(hour.windFromDeg + 180))
                            Text(String(format: "%.0f", hour.windSpeed.value))
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                            Text("kt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if hour.precipitationChance > 0.2 {
                                Text("\(Int((hour.precipitationChance * 100).rounded()))%")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .frame(width: 52)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    WeatherView()
        .environment(LivePositionStore())
        .environment(CourseStateStore())
}
