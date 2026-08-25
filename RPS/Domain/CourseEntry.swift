//
//  CourseEntry.swift
//  RPS
//
//  Ported from the reference app's `course-entry.model.ts`.
//

import Foundation

enum Rounding: String, Codable, Equatable {
    case starboard = "S"
    case port = "P"
}

/// One occurrence of a mark in the course. Wraps a Mark with a per-occurrence
/// uid (so the same mark can appear twice - e.g. a windward mark rounded
/// twice - as two independent, independently-removable entries), a rounding
/// direction, and an optional GPS/manual position override for portable
/// marks or the start pin.
struct CourseEntry: Codable, Identifiable, Equatable {
    var uid: Int
    var mark: Mark
    var overrideLat: Double?
    var overrideLon: Double?
    var rounding: Rounding?

    var id: Int { uid }
}

struct ResolvedPosition: Equatable {
    var lat: Double
    var lon: Double
}

func resolvedPosition(_ entry: CourseEntry) -> ResolvedPosition? {
    if let lat = entry.overrideLat, let lon = entry.overrideLon {
        return ResolvedPosition(lat: lat, lon: lon)
    }
    if let lat = entry.mark.lat, let lon = entry.mark.lon {
        return ResolvedPosition(lat: lat, lon: lon)
    }
    return nil
}

func roundingWord(_ rounding: Rounding?) -> String {
    switch rounding {
    case .starboard: return "leave to starboard"
    case .port: return "leave to port"
    case nil: return ""
    }
}

/// S -> P -> unset -> S ...
func cycleRounding(_ current: Rounding?) -> Rounding? {
    switch current {
    case nil: return .starboard
    case .starboard: return .port
    case .port: return nil
    }
}
