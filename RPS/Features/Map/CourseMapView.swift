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

    @State private var camera: MapCameraPosition = .automatic
    @State private var didInitialFit = false

    private var placedPoints: [MapPoint] { mapPoints.compactMap { $0 } }

    var body: some View {
        Map(position: $camera) {
            courseLineContent
            highlightedLegContent
            startLineContent
            markAnnotations
            boatAnnotation
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onAppear { fitIfNeeded() }
        .onChange(of: placedPoints.count) { _, _ in fitIfNeeded() }
    }

    @MapContentBuilder
    private var courseLineContent: some MapContent {
        if placedPoints.count >= 2 {
            MapPolyline(coordinates: placedPoints.map(\.coordinate))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    @MapContentBuilder
    private var highlightedLegContent: some MapContent {
        if let highlighted = highlightedLegIndex,
           let from = placedPoints[safe: highlighted],
           let to = placedPoints[safe: highlighted + 1] {
            MapPolyline(coordinates: [from.coordinate, to.coordinate])
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
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
    private var markAnnotations: some MapContent {
        ForEach(placedPoints) { point in
            Annotation(point.name, coordinate: point.coordinate) {
                MarkBadge(
                    code: point.label,
                    govtLight: point.govtLight,
                    portable: point.portable,
                    rounding: point.rounding,
                    isStart: point.isStart,
                    size: 30
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

    private func fitIfNeeded() {
        guard !didInitialFit else { return }
        var coords = placedPoints.map(\.coordinate)
        if let pin { coords.append(pin.coordinate) }
        if let committee { coords.append(committee.coordinate) }
        guard !coords.isEmpty else { return }
        didInitialFit = true
        if coords.count == 1 {
            camera = .region(MKCoordinateRegion(center: coords[0], span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
            return
        }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.01),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.01)
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
