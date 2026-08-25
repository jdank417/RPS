//
//  PositionEntrySheet.swift
//  RPS
//
//  Gives a portable or unpositioned mark a position: drop a pin on the map,
//  use the current GPS fix, or type lat/lon by hand. Its course position
//  must come from one of these — never assumed from a charted lat/lon that
//  doesn't exist.
//

import SwiftUI
import MapKit
import CoreLocation

struct PositionEntrySheet: View {
    let markLabel: String
    let initial: CLLocationCoordinate2D?
    let liveFix: CLLocationCoordinate2D?
    let onSave: (Double, Double, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin: CLLocationCoordinate2D
    @State private var camera: MapCameraPosition
    @State private var latText: String
    @State private var lonText: String
    @State private var mode: Mode = .map

    private enum Mode: String, CaseIterable { case map = "Map", manual = "Type" }

    init(markLabel: String, initial: CLLocationCoordinate2D?, liveFix: CLLocationCoordinate2D?, onSave: @escaping (Double, Double, String) -> Void) {
        self.markLabel = markLabel
        self.initial = initial
        self.liveFix = liveFix
        self.onSave = onSave
        let start = initial ?? liveFix ?? CLLocationCoordinate2D(latitude: 42.35, longitude: -71.05)
        _pin = State(initialValue: start)
        _camera = State(initialValue: .region(MKCoordinateRegion(center: start, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))))
        _latText = State(initialValue: initial.map { String(format: "%.5f", $0.latitude) } ?? "")
        _lonText = State(initialValue: initial.map { String(format: "%.5f", $0.longitude) } ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if mode == .map {
                    mapEditor
                } else {
                    manualEditor
                }

                if let liveFix {
                    Button {
                        pin = liveFix
                        latText = String(format: "%.5f", liveFix.latitude)
                        lonText = String(format: "%.5f", liveFix.longitude)
                        camera = .region(MKCoordinateRegion(center: liveFix, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                    } label: {
                        Label("Use current GPS position", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding([.horizontal, .bottom])
                }
            }
            .navigationTitle("Place \(markLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let source = mode == .map ? "map pin" : "manual entry"
                        onSave(pin.latitude, pin.longitude, source)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        if mode == .manual {
            return Double(latText) != nil && Double(lonText) != nil
        }
        return true
    }

    private var mapEditor: some View {
        MapReader { proxy in
            Map(position: $camera) {
                Marker(markLabel, coordinate: pin)
                    .tint(.orange)
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    pin = coordinate
                    latText = String(format: "%.5f", coordinate.latitude)
                    lonText = String(format: "%.5f", coordinate.longitude)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
        }
        .overlay(alignment: .top) {
            Text("Tap the map to drop the pin")
                .font(.footnote)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
        }
    }

    private var manualEditor: some View {
        Form {
            Section("Latitude") {
                TextField("42.35000", text: $latText)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.monospaced())
                    .onChange(of: latText) { _, new in syncPinFromManual() }
            }
            Section("Longitude") {
                TextField("-71.05000", text: $lonText)
                    .keyboardType(.numbersAndPunctuation)
                    .font(.body.monospaced())
                    .onChange(of: lonText) { _, new in syncPinFromManual() }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func syncPinFromManual() {
        guard let lat = Double(latText), let lon = Double(lonText), (-90...90).contains(lat), (-180...180).contains(lon) else { return }
        pin = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
