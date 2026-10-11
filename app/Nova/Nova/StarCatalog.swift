//
//  StarCatalog.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation


enum StarCatalog {
    private struct Row: Decodable {
        let id: String, name: String
        let ra: Double, dec: Double, mag: Double
        let ly: Int
        let con: String, spect: String
    }

    private static let rows: [Row] = {
        guard let url = Bundle.main.url(forResource: "stars", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        return decoded
    }()

    static var count: Int { rows.count }
    static var isLoaded: Bool { !rows.isEmpty }

    static func objects(excluding existing: [CelestialObject]) -> [CelestialObject] {
        guard !rows.isEmpty else { return [] }
        let names = Set(existing.map { normalize($0.name) })
        var placed: [(ra: Double, dec: Double)] = existing.compactMap {
            if case .fixedJ2000(let ra, let dec)? = $0.source { return (ra, dec) }
            return nil
        }
        var out: [CelestialObject] = []
        var seenIDs = Set(existing.map(\.id)), seenNames = names
        for r in rows {
            let id = "star-" + r.id
            guard r.mag < 7, r.dec >= -90, r.dec <= 90, r.ra >= 0, r.ra < 360,
                  !seenIDs.contains(id), !seenNames.contains(normalize(r.name)) else { continue }
            if placed.contains(where: { abs($0.dec - r.dec) < 0.3 && abs(($0.ra - r.ra) * cos(r.dec * .pi / 180)) < 0.3 }) { continue }
            seenIDs.insert(id); seenNames.insert(normalize(r.name)); placed.append((r.ra, r.dec))
            out.append(make(r, id: id))
        }
        return out
    }


    private static func make(_ r: Row, id: String) -> CelestialObject {
        let (colorWord, hotCool) = color(for: r.spect)
        let mag = magnitudeText(r.mag)
        let brightness: String
        switch r.mag {
        case ..<1.5: brightness = "one of the brightest stars in the whole sky"
        case ..<2.5: brightness = "a bright star, easy to see from a dark place"
        case ..<3.5: brightness = "a fairly bright star"
        default: brightness = "a fainter star, visible to the unaided eye only from a reasonably dark place"
        }
        let distance = "about \(grouped(r.ly)) light-years"
        let short = "\(r.name) is a \(colorWord) star in \(r.con), \(brightness)."
        var deeper = "\(r.name) has a brightness of magnitude \(mag). On this scale, smaller or more negative numbers are brighter. "
        deeper += "Its light is \(colorWord), which usually means it is \(hotCool). "
        deeper += "It is \(distance) away, so the light you would see left it about that many years ago."
        let fact = "Star colors tell you temperature: blue-white stars are the hottest and red stars the coolest. \(r.name) is \(colorWord)."
        return Catalog.star(id, r.name, r.name, ra: r.ra, dec: r.dec, mag: r.mag, dist: distance, con: r.con,
                            short: short, deeper: deeper, story: nil, fact: fact)
    }

    private static func color(for spect: String) -> (String, String) {
        switch spect.trimmingCharacters(in: .whitespaces).first?.uppercased() {
        case "O": return ("blue", "extremely hot")
        case "B": return ("blue-white", "very hot")
        case "A": return ("white", "hot")
        case "F": return ("yellow-white", "a little hotter than the Sun")
        case "G": return ("yellow", "similar in temperature to the Sun")
        case "K": return ("orange", "cooler than the Sun")
        case "M": return ("red-orange", "relatively cool")
        default: return ("white", "of a temperature this catalog doesn't list")
        }
    }

    private static func magnitudeText(_ m: Double) -> String {
        m < 0 ? "minus \(String(format: "%.1f", -m))" : String(format: "%.1f", m)
    }

    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }
}
