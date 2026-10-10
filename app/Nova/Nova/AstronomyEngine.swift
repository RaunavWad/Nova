//
//  AstronomyEngine.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation

// MARK: - Basic types (all angles in degrees)

struct Horizontal: Equatable {
    var azimuth: Double   // 0 = true north, 90 = east, clockwise
    var altitude: Double  // 0 = horizon, 90 = zenith
}

struct Equatorial: Equatable {
    var ra: Double   // degrees, 0..360
    var dec: Double  // degrees
}

enum PlanetID: String, Hashable { case jupiter, saturn }

// MARK: - Engine

/// Low-precision, self-contained astronomy. Accuracy (typical):
///  - Stars: < 0.05° (J2000 catalog position + IAU-1976 precession; proper motion ignored, <0.02° for these stars)
///  - Moon: ~0.3° (Meeus abridged series) plus topocentric parallax correction in altitude
///  - Planets: ~0.1–0.3° (JPL Keplerian elements, valid 1800–2050)
///  - No atmospheric refraction (up to ~0.5° at the horizon, <0.05° above 30° altitude)
/// All of this is far better than the phone's pointing accuracy (several degrees).
enum AstronomyEngine {

    // MARK: Angle helpers
    @inline(__always) static func rad(_ d: Double) -> Double { d * .pi / 180 }
    @inline(__always) static func deg(_ r: Double) -> Double { r * 180 / .pi }
    static func norm360(_ d: Double) -> Double {
        let r = d.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
    static func norm180(_ d: Double) -> Double {
        var r = norm360(d)
        if r > 180 { r -= 360 }
        return r
    }

    // MARK: Time
    static func julianDate(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5   // Unix epoch is JD 2440587.5 (UTC; time zone irrelevant)
    }
    static func centuries(_ jd: Double) -> Double { (jd - 2451545.0) / 36525.0 }

    /// Greenwich mean sidereal time in degrees.
    static func gmst(jd: Double) -> Double {
        let T = centuries(jd)
        return norm360(280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * T * T)
    }

    // MARK: Precession (Meeus ch. 21, IAU 1976), J2000 -> mean equator of date
    static func precess(_ eq: Equatorial, T: Double) -> Equatorial {
        let zeta = rad((2306.2181 * T + 0.30188 * T * T) / 3600)
        let z = rad((2306.2181 * T + 1.09468 * T * T) / 3600)
        let theta = rad((2004.3109 * T - 0.42665 * T * T) / 3600)
        let a = rad(eq.ra), d = rad(eq.dec)
        let A = cos(d) * sin(a + zeta)
        let B = cos(theta) * cos(d) * cos(a + zeta) - sin(theta) * sin(d)
        let C = sin(theta) * cos(d) * cos(a + zeta) + cos(theta) * sin(d)
        let ra = norm360(deg(atan2(A, B)) + deg(z))
        let dec = deg(asin(max(-1, min(1, C))))
        return Equatorial(ra: ra, dec: dec)
    }

    // MARK: Equatorial (of date) -> horizontal
    static func horizontal(from eq: Equatorial, jd: Double, latitude: Double, longitude: Double) -> Horizontal {
        let lst = norm360(gmst(jd: jd) + longitude)        // east longitude positive
        let H = rad(lst - eq.ra)                           // hour angle, west positive
        let d = rad(eq.dec), phi = rad(latitude)
        let north = sin(d) * cos(phi) - cos(d) * sin(phi) * cos(H)
        let east = -cos(d) * sin(H)
        let up = sin(d) * sin(phi) + cos(d) * cos(phi) * cos(H)
        return Horizontal(azimuth: norm360(deg(atan2(east, north))),
                          altitude: deg(asin(max(-1, min(1, up)))))
    }

    // MARK: Sun (low precision, Meeus ch. 25) — used for twilight and Moon phase
    static func sunEclipticLongitude(T: Double) -> Double {
        let L0 = 280.46646 + 36000.76983 * T
        let M = rad(357.52911 + 35999.05029 * T)
        let C = 1.914602 * sin(M) + 0.019993 * sin(2 * M)
        return norm360(L0 + C - 0.00569)
    }
    static func obliquity(T: Double) -> Double { 23.439291 - 0.0130042 * T }

    static func eclipticToEquatorial(lon: Double, lat: Double, T: Double) -> Equatorial {
        let l = rad(lon), b = rad(lat), e = rad(obliquity(T: T))
        let ra = atan2(sin(l) * cos(e) - tan(b) * sin(e), cos(l))
        let dec = asin(sin(b) * cos(e) + cos(b) * sin(e) * sin(l))
        return Equatorial(ra: norm360(deg(ra)), dec: deg(dec))
    }

    static func sunHorizontal(date: Date, latitude: Double, longitude: Double) -> Horizontal {
        let jd = julianDate(date), T = centuries(jd)
        let eq = eclipticToEquatorial(lon: sunEclipticLongitude(T: T), lat: 0, T: T)
        return horizontal(from: eq, jd: jd, latitude: latitude, longitude: longitude)
    }

    // MARK: Moon (Meeus abridged, ~0.3°)
    struct MoonState { var equatorial: Equatorial; var distanceKm: Double; var eclipticLongitude: Double }

    static func moon(T: Double) -> MoonState {
        let Lp = norm360(218.3164477 + 481267.88123421 * T)
        let D = rad(norm360(297.8501921 + 445267.1114034 * T))
        let M = rad(norm360(357.5291092 + 35999.0502909 * T))
        let Mp = rad(norm360(134.9633964 + 477198.8675055 * T))
        let F = rad(norm360(93.2720950 + 483202.0175233 * T))
        let lon = Lp + 6.289 * sin(Mp) + 1.274 * sin(2 * D - Mp) + 0.658 * sin(2 * D)
            + 0.214 * sin(2 * Mp) - 0.186 * sin(M) - 0.114 * sin(2 * F)
            + 0.059 * sin(2 * D - 2 * Mp) + 0.057 * sin(2 * D - M - Mp) + 0.053 * sin(2 * D + Mp)
        let lat = 5.128 * sin(F) + 0.281 * sin(Mp + F) + 0.278 * sin(Mp - F) + 0.173 * sin(2 * D - F)
        let dist = 385001.0 - 20905.0 * cos(Mp) - 3699.0 * cos(2 * D - Mp) - 2956.0 * cos(2 * D)
        return MoonState(equatorial: eclipticToEquatorial(lon: norm360(lon), lat: lat, T: T),
                         distanceKm: dist, eclipticLongitude: norm360(lon))
    }

    /// Returns illuminated fraction 0...1 and a spoken phase name.
    static func moonPhase(date: Date) -> (fraction: Double, name: String) {
        let T = centuries(julianDate(date))
        let elong = norm360(moon(T: T).eclipticLongitude - sunEclipticLongitude(T: T))
        let fraction = (1 - cos(rad(elong))) / 2
        let name: String
        switch elong {
        case 0..<22.5, 337.5..<360: name = "new moon"
        case 22.5..<67.5: name = "waxing crescent"
        case 67.5..<112.5: name = "first quarter"
        case 112.5..<157.5: name = "waxing gibbous"
        case 157.5..<202.5: name = "full moon"
        case 202.5..<247.5: name = "waning gibbous"
        case 247.5..<292.5: name = "last quarter"
        default: name = "waning crescent"
        }
        return (fraction, name)
    }

    // MARK: Planets (JPL Standish Keplerian elements, 1800–2050; values per Julian century)
    private struct Elements {
        let a: (Double, Double), e: (Double, Double), I: (Double, Double)
        let L: (Double, Double), w: (Double, Double), O: (Double, Double)
    }
    private static let earthEl = Elements(a: (1.00000261, 0.00000562), e: (0.01671123, -0.00004392),
                                          I: (-0.00001531, -0.01294668), L: (100.46457166, 35999.37244981),
                                          w: (102.93768193, 0.32327364), O: (0, 0))
    private static let jupiterEl = Elements(a: (5.20288700, -0.00011607), e: (0.04838624, -0.00013253),
                                            I: (1.30439695, -0.00183714), L: (34.39644051, 3034.74612775),
                                            w: (14.72847983, 0.21252668), O: (100.47390909, 0.20469106))
    private static let saturnEl = Elements(a: (9.53667594, -0.00125060), e: (0.05386179, -0.00050991),
                                           I: (2.48599187, 0.00193609), L: (49.95424423, 1222.49362201),
                                           w: (92.59887831, -0.41897216), O: (113.66242448, -0.28867794))

    /// Heliocentric ecliptic J2000 rectangular coordinates, AU.
    private static func heliocentric(_ el: Elements, T: Double) -> (x: Double, y: Double, z: Double) {
        let a = el.a.0 + el.a.1 * T, e = el.e.0 + el.e.1 * T, I = rad(el.I.0 + el.I.1 * T)
        let L = el.L.0 + el.L.1 * T, w = el.w.0 + el.w.1 * T, O = el.O.0 + el.O.1 * T
        let M = rad(norm180(L - w))
        var E = M + e * sin(M)
        for _ in 0..<12 { E -= (E - e * sin(E) - M) / (1 - e * cos(E)) }
        let xp = a * (cos(E) - e), yp = a * sqrt(1 - e * e) * sin(E)
        let om = rad(w - O), Om = rad(O)
        let x = (cos(om) * cos(Om) - sin(om) * sin(Om) * cos(I)) * xp + (-sin(om) * cos(Om) - cos(om) * sin(Om) * cos(I)) * yp
        let y = (cos(om) * sin(Om) + sin(om) * cos(Om) * cos(I)) * xp + (-sin(om) * sin(Om) + cos(om) * cos(Om) * cos(I)) * yp
        let z = (sin(om) * sin(I)) * xp + (cos(om) * sin(I)) * yp
        return (x, y, z)
    }

    /// Geocentric equatorial J2000 position and distance (AU).
    static func planetJ2000(_ id: PlanetID, T: Double) -> (eq: Equatorial, distanceAU: Double) {
        let p = heliocentric(id == .jupiter ? jupiterEl : saturnEl, T: T)
        let e = heliocentric(earthEl, T: T)
        let gx = p.x - e.x, gy = p.y - e.y, gz = p.z - e.z
        let eps = rad(23.43928)
        let xe = gx, ye = gy * cos(eps) - gz * sin(eps), ze = gy * sin(eps) + gz * cos(eps)
        let ra = norm360(deg(atan2(ye, xe)))
        let dec = deg(atan2(ze, sqrt(xe * xe + ye * ye)))
        return (Equatorial(ra: ra, dec: dec), sqrt(gx * gx + gy * gy + gz * gz))
    }

    // MARK: Public position API
    /// Current horizontal position of a catalog object, or nil if it is not locatable (educational-only).
    static func position(of object: CelestialObject, date: Date, latitude: Double, longitude: Double) -> Horizontal? {
        guard let source = object.source else { return nil }
        let jd = julianDate(date), T = centuries(jd)
        switch source {
        case .fixedJ2000(let ra, let dec):
            let eq = precess(Equatorial(ra: ra, dec: dec), T: T)
            return horizontal(from: eq, jd: jd, latitude: latitude, longitude: longitude)
        case .planet(let id):
            let eq = precess(planetJ2000(id, T: T).eq, T: T)
            return horizontal(from: eq, jd: jd, latitude: latitude, longitude: longitude)
        case .moon:
            let m = moon(T: T)
            var h = horizontal(from: m.equatorial, jd: jd, latitude: latitude, longitude: longitude)
            // Topocentric parallax (up to ~1°) lowers the apparent altitude.
            let parallax = deg(asin(6378.14 / m.distanceKm))
            h.altitude -= parallax * cos(rad(h.altitude))
            return h
        }
    }

    // MARK: Geometry
    /// Great-circle angle between two directions, degrees.
    static func separation(_ a: Horizontal, _ b: Horizontal) -> Double {
        let a1 = rad(a.azimuth), h1 = rad(a.altitude), a2 = rad(b.azimuth), h2 = rad(b.altitude)
        let c = sin(h1) * sin(h2) + cos(h1) * cos(h2) * cos(a1 - a2)
        return deg(acos(max(-1, min(1, c))))
    }

    static func compassWord(_ azimuth: Double) -> String {
        let names = ["north", "north-northeast", "northeast", "east-northeast", "east", "east-southeast",
                     "southeast", "south-southeast", "south", "south-southwest", "southwest",
                     "west-southwest", "west", "west-northwest", "northwest", "north-northwest"]
        let i = Int((norm360(azimuth) + 11.25) / 22.5) % 16
        return names[i]
    }

    /// "about 40 degrees up in the east-southeast"
    static func describeLocation(_ h: Horizontal) -> String {
        if h.altitude < 0 { return "below the horizon, toward the \(compassWord(h.azimuth))" }
        let alt = Int((h.altitude / 5).rounded()) * 5
        if h.altitude > 80 { return "almost straight overhead" }
        return "about \(max(alt, 5)) degrees above the \(compassWord(h.azimuth)) horizon"
    }
}
