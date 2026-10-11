//
//  ObjectMatcher.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation

enum MatchResult {
    case confident(CelestialObject, separation: Double)
    case ambiguous([(object: CelestialObject, separation: Double)])
    case nothingNear(nearest: CelestialObject, separation: Double, dAzimuth: Double, dAltitude: Double)
    case belowHorizon
    case unreliable(String)
}

enum ObjectMatcher {
    static let objectExtent = 2.0

    static func match(pointing: Horizontal, uncertainty: Double, date: Date, latitude: Double, longitude: Double,
                      objects: [CelestialObject] = Catalog.locatable) -> MatchResult {
        if pointing.altitude < -8 { return .belowHorizon }
        let tolerance = uncertainty + objectExtent
        var entries: [(object: CelestialObject, separation: Double, pos: Horizontal)] = []
        for o in objects {
            guard let p = AstronomyEngine.position(of: o, date: date, latitude: latitude, longitude: longitude),
                  p.altitude > -1 else { continue }
            entries.append((o, AstronomyEngine.separation(pointing, p), p))
        }
        entries.sort { $0.separation < $1.separation }

        let close = entries.filter { $0.separation <= tolerance }
        if close.isEmpty {
            guard let n = entries.first else { return .belowHorizon }
            return .nothingNear(nearest: n.object, separation: n.separation,
                                dAzimuth: AstronomyEngine.norm180(n.pos.azimuth - pointing.azimuth),
                                dAltitude: n.pos.altitude - pointing.altitude)
        }
        if close.count == 1 { return .confident(close[0].object, separation: close[0].separation) }
        // Several plausible: confident only if the best is clearly closer than the runner-up.
        if close[1].separation - close[0].separation > uncertainty {
            return .confident(close[0].object, separation: close[0].separation)
        }
        return .ambiguous(close.prefix(3).map { ($0.object, $0.separation) })
    }

    static func relativeDirection(dAzimuth: Double, dAltitude: Double) -> String {
        var parts: [String] = []
        let az = Int((abs(dAzimuth) / 5).rounded()) * 5
        if az >= 5 { parts.append("\(az) degrees to the \(dAzimuth > 0 ? "right" : "left")") }
        let alt = Int((abs(dAltitude) / 5).rounded()) * 5
        if alt >= 5 { parts.append("\(alt) degrees \(dAltitude > 0 ? "higher" : "lower")") }
        return parts.isEmpty ? "right where you are pointing" : parts.joined(separator: " and ")
    }
}
