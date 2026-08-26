//
//  CourseMapView.swift
//  RPS
//
//  Plots the resolved course as a connected path, with mark icons
//  distinguishing portable vs. charted marks and rounding direction, and
//  (in Race Mode) the boat's live position/heading overlaid. iOS 17+ SwiftUI
//  `Map` API.
//

import SwiftUI
import MapKit

struct CourseMapView: View {
    let mapPoints: [MapPoint?]
    var liveFix: LiveFix? = nil
    var pin: GeoMath.LatLon? = nil
    var committee: GeoMath.LatLon? = nil
    var highlightedLegIndex: Int? = nil
    /// Extra bottom inset so overlaid chrome (the leg toolbar in Race Mode)
    /// never sits on top of the course itself.
    var bottomContentInset: CGFloat = 0

    @State private var camera: MapCameraPosition = .automatic
    /// The map's current rotation. Annotations stay upright relative to the
    /// screen, so a leg arrow drawn at a true bearing would point the wrong
    /// way the moment the map is rotated (which follow-boat mode does
    /// continuously). Subtracting the camera's heading keeps the arrow
    /// pointing where the leg actually goes.
    @State private var cameraHeading: Double = 0
    /// The course this camera was last framed for. Re-framing keys off this
    /// rather than a bool, so a course that *changes* re-frames instead of
    /// leaving the sailor looking at the water the last course was on.
    @State private var fittedSignature: String?
    @State private var followBoat = false
    @State private var hybrid = false

    private var placedPoints: [MapPoint] { mapPoints.compactMap { $0 } }

    /// Identifies the current set of plotted positions. Coordinates are
    /// rounded before hashing so GPS jitter on a placed portable mark doesn't
    /// yank the camera back to "fit" every second.
    private var courseSignature: String {
        var parts = placedPoints.map { "\($0.label):\(rounded($0.lat)),\(rounded($0.lon))" }
        if let pin { parts.append("pin:\(rounded(pin.lat)),\(rounded(pin.lon))") }
        if let committee { parts.append("rc:\(rounded(committee.lat)),\(rounded(committee.lon))") }
        return parts.joined(separator: "|")
    }

    private func rounded(_ v: Double) -> Int { Int((v * 10_000).rounded()) }

    /// One direction arrow per leg, at its midpoint.
    private struct LegArrow: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
        let bearing: Double
    }

    private var legArrows: [LegArrow] {
        guard placedPoints.count >= 2 else { return [] }
        return (0..<(placedPoints.count - 1)).compactMap { i in
            let a = placedPoints[i]
            let b = placedPoints[i + 1]
            // A zero-length leg (two marks resolving to the same spot) has no
            // meaningful bearing to draw.
            guard GeoMath.haversineNm(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon) > 0.005 else {
                return nil
            }
            let mid = GeoMath.midpoint(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
            return LegArrow(
                id: i,
                coordinate: CLLocationCoordinate2D(latitude: mid.lat, longitude: mid.lon),
                bearing: GeoMath.initialBearing(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
            )
        }
    }

    var body: some View {
        Map(position: $camera) {
            courseLineContent
            highlightedLegContent
            startLineContent
            legArrowContent
            markAnnotations
            boatAnnotation
        }
        .onMapCameraChange(frequency: .continuous) { context in
            // Only when it has moved enough to matter: this fires on every
            // frame of a pan or zoom, and rewriting state each time would
            // re-render the whole map for a rotation nobody can see.
            let heading = context.camera.heading
            if abs(heading - cameraHeading) > 1 { cameraHeading = heading }
        }
        .mapStyle(hybrid ? .hybrid(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaPadding(.bottom, bottomContentInset)
        .overlay(alignment: .topTrailing) { mapButtons }
        .onAppear { fitIfCourseChanged() }
        .onChange(of: courseSignature) { _, _ in fitIfCourseChanged() }
        .onChange(of: liveFix) { _, fix in
            guard followBoat, let fix else { return }
            camera = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: 1_500, heading: fix.headingDeg ?? 0))
        }
    }

    // MARK: - Controls

    private var mapButtons: some View {
        VStack(spacing: 8) {
            mapButton(
                systemImage: followBoat ? "location.fill" : "location",
                isOn: followBoat,
                label: "Follow boat"
            ) {
                followBoat.toggle()
                if followBoat, let fix = liveFix {
                    camera = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: 1_500, heading: fix.headingDeg ?? 0))
                }
            }
            .disabled(liveFix == nil)

            mapButton(systemImage: "arrow.up.left.and.arrow.down.right", isOn: false, label: "Fit course") {
                followBoat = false
                fitToCourse()
            }

            mapButton(systemImage: hybrid ? "globe.americas.fill" : "map", isOn: hybrid, label: "Satellite") {
                hybrid.toggle()
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 12)
    }

    private func mapButton(systemImage: String, isOn: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                // 44pt is Apple's minimum comfortable tap target, and this is
                // a control pressed on a moving boat.
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .accessibilityLabel(label)
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }

    // MARK: - Map content

    @MapContentBuilder
    private var courseLineContent: some MapContent {
        if placedPoints.count >= 2 {
            MapPolyline(coordinates: placedPoints.map(\.coordinate))
                .stroke(
                    Color.accentColor.opacity(0.55),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
        }
    }

    /// The active leg, drawn over the course line.
    ///
    /// Wider than the base line and fully opaque on purpose: at 6pt over a
    /// 3pt line the blue showed through along the edges and at the joins,
    /// which read as two lines fighting rather than one leg picked out of
    /// the course. A round cap at 8pt covers the base stroke and its joins
    /// completely, and the base line being semi-transparent keeps the
    /// contrast between "the course" and "the leg you are sailing".
    @MapContentBuilder
    private var highlightedLegContent: some MapContent {
        if let highlighted = highlightedLegIndex,
           let from = placedPoints[safe: highlighted],
           let to = placedPoints[safe: highlighted + 1] {
            MapPolyline(coordinates: [from.coordinate, to.coordinate])
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        }
    }

    @MapContentBuilder
    private var startLineContent: some MapContent {
        if let pin, let committee {
            MapPolyline(coordinates: [pin.coordinate, committee.coordinate])
                .stroke(.primary, style: StrokeStyle(lineWidth: 2, dash: [1, 6]))
            Annotation("Pin", coordinate: pin.coordinate) {
                lineEndMarker(label: "Pin", systemImage: "mappin")
            }
            Annotation("RC", coordinate: committee.coordinate) {
                lineEndMarker(label: "RC", systemImage: "flag.fill")
            }
        }
    }

    @MapContentBuilder
    private var legArrowContent: some MapContent {
        ForEach(legArrows) { arrow in
            Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                LegDirectionArrow(isActive: arrow.id == highlightedLegIndex)
                    .rotationEffect(.degrees(arrow.bearing - cameraHeading))
                    .allowsHitTesting(false)
            }
            .annotationTitles(.hidden)
        }
    }

    @MapContentBuilder
    private var markAnnotations: some MapContent {
        ForEach(placedPoints) { point in
            Annotation(point.name, coordinate: point.coordinate) {
                MarkBadge(
                    code: point.label,
                    govtLight: point.govtLight,
                    portable: point.portable,
                    rounding: point.rounding,
                    isStart: point.isStart,
                    size: 32
                )
            }
        }
    }

    @MapContentBuilder
    private var boatAnnotation: some MapContent {
        if let liveFix {
            Annotation("Boat", coordinate: liveFix.coordinate) {
                BoatMarker(headingDeg: liveFix.headingDeg)
            }
        }
    }

    private func lineEndMarker(label: String, systemImage: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .padding(6)
                .background(.thinMaterial, in: Circle())
            Text(label).font(.caption2.weight(.semibold))
        }
    }

    // MARK: - Camera

    private func fitIfCourseChanged() {
        let signature = courseSignature
        guard !signature.isEmpty, signature != fittedSignature else { return }
        guard !followBoat else { return }
        fittedSignature = signature
        fitToCourse()
    }

    private func fitToCourse() {
        var coords = placedPoints.map(\.coordinate)
        if let pin { coords.append(pin.coordinate) }
        if let committee { coords.append(committee.coordinate) }
        guard !coords.isEmpty else { return }

        if coords.count == 1 {
            camera = .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
            return
        }

        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        // 1.9x rather than a tight fit: marks sitting hard against the screen
        // edge (or under the leg toolbar) read as a course running off the
        // map. The floor keeps a two-mark course from zooming absurdly close.
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.9, 0.012),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.9, 0.012)
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct BoatMarker: View {
    let headingDeg: Double?
    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 18))
            .foregroundStyle(.white)
            .padding(8)
            .background(Color.blue, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .rotationEffect(.degrees(headingDeg ?? 0))
            .shadow(radius: 2)
    }
}

extension MapPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

extension GeoMath.LatLon {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
