//
//  WeatherView.swift
//  RPS
//
//  What WeatherKit adds beyond the plain forecast wind used mid-race:
//  current conditions, pressure and its trend, visibility, UV - and, the
//  reason this tab exists, a wind map plus an hourly trend so a crew can see
//  whether the breeze is building, dying, or shifting over the next few
//  hours rather than only knowing what it's doing right now.
//

import SwiftUI
import MapKit

struct WeatherView: View {
    @Environment(LivePositionStore.self) private var liveStore
    @Environment(CourseStateStore.self) private var course
    @State private var service = RaceWeatherService()

    /// How many of the fetched hours to actually show - the one bit of
    /// customization this tab offers. Persisted, so the choice sticks
    /// between races rather than resetting every launch.
    @AppStorage("rps.weather.hourWindow") private var hourWindow = 6
    @AppStorage("rps.weather.showMap") private var showMap = true

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

    private var coordinate: CLLocationCoordinate2D? {
        guard let location else { return nil }
        return CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon)
    }

    private var locationSourceText: String {
        liveStore.fix != nil ? "Your position" : "Course start"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let snapshot = service.snapshot {
                        if showMap, let coordinate {
                            windMap(coordinate: coordinate, snapshot: snapshot)
                        }
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
                            Label("WeatherKit not available", systemImage: "exclamationmark.triangle.fill")
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Show wind map", isOn: $showMap)
                        Picker("Forecast window", selection: $hourWindow) {
                            Text("6 hours").tag(6)
                            Text("12 hours").tag(12)
                            Text("24 hours").tag(24)
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
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

    // MARK: - Wind map

    /// A third of the page, per the brief: the local chart with the same
    /// drifting wind-streak field used on the course map, so the current
    /// breeze reads as a picture rather than a number. WeatherKit only
    /// gives a single point sample, not a spatial grid, so this is
    /// deliberately not claiming to show a wind field across the area -
    /// just this one reading, in the place it applies, which is what a crew
    /// actually has to work with here.
    private func windMap(coordinate: CLLocationCoordinate2D, snapshot: RaceWeatherSnapshot) -> some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 4000, heading: 0))) {
            if liveStore.fix != nil {
                Annotation("You", coordinate: coordinate) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Color.blue, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .rotationEffect(.degrees(liveStore.fix?.headingDeg ?? 0))
                        .shadow(radius: 2)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay {
            WindFlowOverlay(windFromDeg: snapshot.windFromDeg, cameraHeading: 0)
        }
        .overlay(alignment: .bottomLeading) {
            Label(
                "\(SailingMath.compassPoint(snapshot.windFromDeg)) \(Int(snapshot.windFromDeg.rounded()))°T · \(String(format: "%.0f", snapshot.windSpeed.value)) kt",
                systemImage: "wind"
            )
            .font(.caption.weight(.semibold))
            .padding(8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(10)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // Forces the map to re-center when the boat has moved meaningfully,
        // since `initialPosition` (deliberately, to allow free panning
        // without fighting a bound camera) otherwise only applies once.
        .id(String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude))
    }

    // MARK: - Current conditions

    private func currentCard(_ snapshot: RaceWeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(locationSourceText, systemImage: "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(service.stale ? "Updated \(ageText(snapshot.observedAt)) · stale" : "Updated \(ageText(snapshot.observedAt))")
                    .font(.caption)
                    .foregroundStyle(service.stale ? Color.orange : Color.secondary)
            }

            HStack(spacing: 12) {
                Image(systemName: snapshot.symbolName)
                    .font(.system(size: 36))
                    .symbolRenderingMode(.multicolor)
                Text(snapshot.temperature.formatted())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(snapshot.windFromDeg + 180))
                Text(String(format: "%.0f kt", snapshot.windSpeed.value))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("\(SailingMath.compassPoint(snapshot.windFromDeg)) · \(Int(snapshot.windFromDeg.rounded()))°T")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let gust = snapshot.gust {
                    Spacer(minLength: 8)
                    Text(String(format: "Gusts %.0f kt", gust.value))
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                value: String(format: "%.0f hPa", snapshot.pressure.converted(to: .hectopascals).value),
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
    /// shifting over the chosen window - not just what it's doing now.
    private func hourlyTrend(_ allHours: [HourlyWindPoint]) -> some View {
        let hours = Array(allHours.prefix(hourWindow))
        let trend = trendLabels(hours)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WIND TREND")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                Text("next \(hours.count)h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let trend {
                HStack(spacing: 16) {
                    Label(trend.direction.text, systemImage: trend.direction.symbol)
                    Label(trend.speed.text, systemImage: trend.speed.symbol)
                }
                .font(.caption.weight(.semibold))
            }

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

    /// Net direction shift and speed change across the shown window - the
    /// two things that actually change a race plan mid-course.
    private func trendLabels(_ hours: [HourlyWindPoint]) -> (direction: (text: String, symbol: String), speed: (text: String, symbol: String))? {
        guard hours.count >= 2, let first = hours.first, let last = hours.last else { return nil }
        let shift = GeoMath.signedAngleDiff(target: last.windFromDeg, from: first.windFromDeg)
        let speedDelta = last.windSpeed.value - first.windSpeed.value
        return (directionTrendLabel(shift), speedTrendLabel(speedDelta))
    }

    /// Positive is a clockwise (veering) shift, negative counter-clockwise
    /// (backing) - the same signed convention `GeoMath.signedAngleDiff`
    /// already uses everywhere else in the app.
    private func directionTrendLabel(_ shiftDeg: Double) -> (text: String, symbol: String) {
        if shiftDeg > 8 { return ("Veering \(Int(shiftDeg.rounded()))°", "arrow.clockwise") }
        if shiftDeg < -8 { return ("Backing \(Int(abs(shiftDeg).rounded()))°", "arrow.counterclockwise") }
        return ("Direction steady", "arrow.left.and.right")
    }

    private func speedTrendLabel(_ deltaKt: Double) -> (text: String, symbol: String) {
        if deltaKt > 1.5 { return ("Building \(Int(deltaKt.rounded())) kt", "arrow.up") }
        if deltaKt < -1.5 { return ("Easing \(Int(abs(deltaKt).rounded())) kt", "arrow.down") }
        return ("Speed steady", "arrow.left.and.right")
    }
}

#Preview {
    WeatherView()
        .environment(LivePositionStore())
        .environment(CourseStateStore())
}
