//
//  WeatherView.swift
//  RPS
//
//  What WeatherKit (and, for water current, NOAA) adds beyond the plain
//  forecast wind used mid-race: current conditions, pressure and its trend,
//  visibility, UV - and, the reason this tab exists, a map (with the
//  plotted course and a wind/current picture over it) plus hourly trends so
//  a crew can see whether the breeze and the water are building, dying, or
//  shifting over the next few hours rather than only knowing what they're
//  doing right now.
//

import SwiftUI
import MapKit

struct WeatherView: View {
    @Environment(LivePositionStore.self) private var liveStore
    @Environment(CourseStateStore.self) private var course
    @Environment(TidalCurrentService.self) private var tidalService
    @State private var service = RaceWeatherService()
    @State private var showCustomizeSheet = false

    /// How many of the fetched hours to actually show. Persisted, so the
    /// choice sticks between races rather than resetting every launch.
    @AppStorage("rps.weather.hourWindow") private var hourWindow = 6
    @AppStorage("rps.weather.showMap") private var showMap = true

    /// Which metric fills each of the four stat tiles - the other bit of
    /// customization this tab offers, stored by `WeatherMetric.rawValue`
    /// rather than the enum itself so `@AppStorage` doesn't need it to be
    /// a primitive type.
    @AppStorage("rps.weather.panel0") private var panel0Raw = WeatherMetric.pressure.rawValue
    @AppStorage("rps.weather.panel1") private var panel1Raw = WeatherMetric.visibility.rawValue
    @AppStorage("rps.weather.panel2") private var panel2Raw = WeatherMetric.humidity.rawValue
    @AppStorage("rps.weather.panel3") private var panel3Raw = WeatherMetric.uvIndex.rawValue

    private var panels: [WeatherMetric] {
        [panel0Raw, panel1Raw, panel2Raw, panel3Raw].map { WeatherMetric(rawValue: $0) ?? .pressure }
    }

    /// The boat's live GPS fix when there is one; otherwise the first
    /// resolved position in the built course, so this tab is useful before
    /// GPS has a fix (indoors, at the dock) as long as a course exists.
    private var location: (lat: Double, lon: Double)? {
        if let fix = liveStore.fix { return (fix.lat, fix.lon) }
        if let point = placedCoursePoints.first {
            return (point.lat, point.lon)
        }
        return nil
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let location else { return nil }
        return CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon)
    }

    private var placedCoursePoints: [MapPoint] {
        course.legComputation.mapPoints.compactMap { $0 }
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
                        if let tidal = tidalService.snapshot {
                            currentTrendCard(tidal)
                        } else if let tidalError = tidalService.error {
                            Text(tidalError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
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
                        Toggle("Show map", isOn: $showMap)
                        Picker("Forecast window", selection: $hourWindow) {
                            Text("6 hours").tag(6)
                            Text("12 hours").tag(12)
                            Text("24 hours").tag(24)
                        }
                        Button {
                            showCustomizeSheet = true
                        } label: {
                            Label("Customize panels", systemImage: "square.grid.2x2")
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
            .sheet(isPresented: $showCustomizeSheet) { customizeSheet }
            .task { await load(force: false) }
            .onChange(of: liveStore.fix) { _, _ in Task { await load(force: false) } }
        }
    }

    private func load(force: Bool) async {
        guard let location else { return }
        async let weatherLoad: () = service.refresh(lat: location.lat, lon: location.lon, force: force)
        async let tidalLoad: () = tidalService.refresh(lat: location.lat, lon: location.lon, force: force)
        _ = await (weatherLoad, tidalLoad)
    }

    // MARK: - Panel customization

    private var customizeSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Panel 1", selection: $panel0Raw) { metricPickerOptions }
                    Picker("Panel 2", selection: $panel1Raw) { metricPickerOptions }
                    Picker("Panel 3", selection: $panel2Raw) { metricPickerOptions }
                    Picker("Panel 4", selection: $panel3Raw) { metricPickerOptions }
                } footer: {
                    Text("Choose which four readings show on the Weather tab.")
                }
            }
            .navigationTitle("Customize Panels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showCustomizeSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var metricPickerOptions: some View {
        ForEach(WeatherMetric.allCases) { metric in
            Text(metric.displayName).tag(metric.rawValue)
        }
    }

    // MARK: - Wind map

    /// A third of the page, per the brief: the plotted course and the
    /// boat's position, with the same drifting wind-streak field used on
    /// the race map, plus the nearest tidal current reading in the corner.
    /// WeatherKit and NOAA both give a single point sample, not a spatial
    /// grid, so this is deliberately not claiming to show a wind or current
    /// field across the area - just the one reading each, pictured where
    /// they apply, which is what a crew actually has to work with here.
    private func windMap(coordinate: CLLocationCoordinate2D, snapshot: RaceWeatherSnapshot) -> some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: mapCameraDistance, heading: 0))) {
            courseLineContent
            courseMarkAnnotations
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
        .overlay(alignment: .bottomTrailing) {
            if let current = tidalService.snapshot?.current {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                        .rotationEffect(.degrees(current.towardDeg))
                    Text(String(format: "%.1f kt", current.speedKts))
                        .font(.caption.weight(.semibold))
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(10)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // Forces the map to re-center when the boat has moved meaningfully,
        // since `initialPosition` (deliberately, to allow free panning
        // without fighting a bound camera) otherwise only applies once.
        .id(String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude))
    }

    /// Wide enough that the farthest plotted mark is comfortably in frame,
    /// floored so a single mark (or none) doesn't zoom in absurdly close
    /// and capped so a sprawling course doesn't zoom this "local" picture
    /// out past being useful.
    private var mapCameraDistance: Double {
        guard let coordinate else { return 4000 }
        let maxDistNm = placedCoursePoints.map {
            GeoMath.haversineNm(lat1: coordinate.latitude, lon1: coordinate.longitude, lat2: $0.lat, lon2: $0.lon)
        }.max() ?? 0
        let meters = maxDistNm * 1852 * 2.6
        return min(max(meters, 1200), 20000)
    }

    @MapContentBuilder
    private var courseLineContent: some MapContent {
        if placedCoursePoints.count >= 2 {
            MapPolyline(coordinates: placedCoursePoints.map(\.coordinate))
                .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
    }

    @MapContentBuilder
    private var courseMarkAnnotations: some MapContent {
        ForEach(placedCoursePoints) { point in
            Annotation(point.name, coordinate: point.coordinate) {
                MarkBadge(
                    code: point.label,
                    govtLight: point.govtLight,
                    portable: point.portable,
                    rounding: point.rounding,
                    isStart: point.isStart,
                    size: 26
                )
            }
            .annotationTitles(.hidden)
        }
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
            ForEach(Array(panels.enumerated()), id: \.offset) { _, metric in
                let reading = metric.reading(from: snapshot)
                statTile(title: metric.title, value: reading.value, caption: reading.caption, captionSymbol: reading.symbol)
            }
        }
    }

    /// A fixed height regardless of content, and the caption row is always
    /// present (just invisible when there is none) rather than omitted -
    /// otherwise a tile with a two-line caption (pressure trend) sits
    /// taller than one with none (visibility), and since a `LazyVGrid` only
    /// matches height *within* a row, not across rows, the two rows of
    /// tiles ended up visibly different sizes.
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
            Group {
                if let captionSymbol {
                    Label(caption ?? " ", systemImage: captionSymbol)
                } else {
                    Text(caption ?? " ")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .opacity(caption == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Hourly wind trend

    /// The reason this tab exists: is the breeze building, dying, or
    /// shifting over the chosen window - not just what it's doing now.
    private func hourlyTrend(_ allHours: [HourlyWindPoint]) -> some View {
        let hours = Array(allHours.prefix(hourWindow))
        let trend = windTrendLabels(hours)

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
                        VStack(spacing: 4) {
                            Text(hour.date.formatted(.dateTime.hour()))
                                .font(.caption.weight(.semibold))
                            Image(systemName: hour.symbolName)
                                .font(.subheadline)
                                .symbolRenderingMode(.multicolor)
                            Image(systemName: "arrow.up")
                                .font(.caption)
                                .rotationEffect(.degrees(hour.windFromDeg + 180))
                            Text("\(Int(hour.windFromDeg.rounded()))°")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                        .frame(width: 56)
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
    private func windTrendLabels(_ hours: [HourlyWindPoint]) -> (direction: (text: String, symbol: String), speed: (text: String, symbol: String))? {
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

    // MARK: - Tidal current trend

    /// The other thing that changes a race plan and wind alone doesn't
    /// cover: which way the water itself is moving. Same shape as the wind
    /// trend card on purpose - two things a crew checks the same way,
    /// pictured the same way.
    private func currentTrendCard(_ snapshot: TidalCurrentSnapshot) -> some View {
        let points = Array(snapshot.points.prefix(hourWindow))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CURRENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                Text(String(format: "%@ · %.0f nm", snapshot.stationName, snapshot.stationDistanceNm))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let now = snapshot.current {
                HStack(spacing: 6) {
                    // No +180 here, unlike the wind arrows: NOAA gives
                    // current direction as where the water is flowing
                    // *toward*, so the arrow can point straight there.
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.cyan)
                        .rotationEffect(.degrees(now.towardDeg))
                    Text(String(format: "%.1f kt", now.speedKts))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("toward \(SailingMath.compassPoint(now.towardDeg)) · \(Int(now.towardDeg.rounded()))°T")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if !points.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(points) { point in
                            VStack(spacing: 4) {
                                Text(point.date.formatted(.dateTime.hour()))
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "arrow.up")
                                    .font(.subheadline)
                                    .foregroundStyle(.cyan)
                                    .rotationEffect(.degrees(point.towardDeg))
                                Text("\(Int(point.towardDeg.rounded()))°")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f", point.speedKts))
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                Text("kt")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 56)
                        }
                    }
                    .padding(.vertical, 4)
                }
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
        .environment(TidalCurrentService())
}
