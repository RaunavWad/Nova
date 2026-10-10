//
//  AchievementManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation
import Combine

// MARK: - Achievements

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String                       // SF Symbol, decoration only
    let isMet: (UserProgress) -> Bool
}

struct Mission: Identifiable {
    let id: String
    let title: String
    let detail: String
    let isMet: (UserProgress) -> Bool
    let progressText: (UserProgress) -> String
}

enum Rewards {
    private static func kinds(_ p: UserProgress, _ k: ObjectKind) -> Set<String> {
        Set(p.discoveredIDs.filter { Catalog.object(id: $0)?.kind == k })
    }
    private static func constellations(_ p: UserProgress) -> Set<String> {
        Set(p.discoveredIDs.compactMap { id -> String? in
            guard let o = Catalog.object(id: id), o.kind == .star else { return nil }
            return o.constellation
        })
    }

    static let achievements: [Achievement] = [
        Achievement(id: "first", title: "First Cosmic Discovery", detail: "Discover your first object.", symbol: "sparkle") { $0.discoveries.count >= 1 },
        Achievement(id: "moon", title: "Moon Explorer", detail: "Find the Moon.", symbol: "moon.stars") { $0.discoveredIDs.contains("moon") },
        Achievement(id: "planet", title: "Planet Spotter", detail: "Find a planet.", symbol: "circle.hexagongrid") { !kinds($0, .planet).isEmpty },
        Achievement(id: "stellar", title: "Stellar Explorer", detail: "Discover three different stars.", symbol: "star") { kinds($0, .star).count >= 3 },
        Achievement(id: "constellation", title: "Constellation Learner", detail: "Listen to the description of two constellations.", symbol: "point.3.connected.trianglepath.dotted") {
            $0.learned.filter { Catalog.object(id: $0)?.kind == .constellation }.count >= 2 },
        Achievement(id: "five", title: "Five Objects Discovered", detail: "Discover five different objects.", symbol: "5.circle") { $0.discoveredIDs.count >= 5 },
        Achievement(id: "solar", title: "Solar System Explorer", detail: "Discover the Moon, Jupiter and Saturn.", symbol: "globe") {
            Set(["moon", "jupiter", "saturn"]).isSubset(of: $0.discoveredIDs) },
        Achievement(id: "regular", title: "Night Sky Regular", detail: "Use Nova on five different days. No late nights needed.", symbol: "calendar") { $0.usageDays.count >= 5 }
    ]

    static let missions: [Mission] = [
        Mission(id: "m_moon", title: "Find the Moon", detail: "Use Find or Identify to locate the Moon.",
                isMet: { $0.discoveredIDs.contains("moon") },
                progressText: { $0.discoveredIDs.contains("moon") ? "Done" : "Not yet" }),
        Mission(id: "m_stars3", title: "Discover three bright stars", detail: "Find or identify three different stars.",
                isMet: { kinds($0, .star).count >= 3 },
                progressText: { "\(min(3, kinds($0, .star).count)) of 3" }),
        Mission(id: "m_planet", title: "Learn about a planet", detail: "Listen to the deeper description of Jupiter or Saturn.",
                isMet: { $0.learned.contains("jupiter") || $0.learned.contains("saturn") },
                progressText: { ($0.learned.contains("jupiter") || $0.learned.contains("saturn")) ? "Done" : "Not yet" }),
        Mission(id: "m_two_con", title: "Explore two constellations", detail: "Discover stars from two different constellations.",
                isMet: { constellations($0).count >= 2 },
                progressText: { "\(min(2, constellations($0).count)) of 2" }),
        Mission(id: "m_story", title: "Hear the story behind a star", detail: "Listen to the story of any star.",
                isMet: { p in p.storiesHeard.contains { Catalog.object(id: $0)?.kind == .star } },
                progressText: { p in p.storiesHeard.contains { Catalog.object(id: $0)?.kind == .star } ? "Done" : "Not yet" })
    ]

    /// An optional, low-pressure daily suggestion. No streaks, no penalties.
    static func dailySuggestion(on date: Date = Date()) -> CelestialObject {
        let stars = Catalog.all.filter { $0.kind == .star || $0.kind == .constellation }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        return stars[day % stars.count]
    }
}

@MainActor
final class AchievementManager: ObservableObject {
    private let persistence: PersistenceManager
    private let speech: SpeechManager
    private let audio: AudioManager
    private let haptics: HapticsManager

    init(persistence: PersistenceManager, speech: SpeechManager, audio: AudioManager, haptics: HapticsManager) {
        self.persistence = persistence; self.speech = speech; self.audio = audio; self.haptics = haptics
    }

    /// Checks all achievements and celebrates newly unlocked ones (speech + sound + haptics + VoiceOver announcement).
    @discardableResult
    func evaluate() -> [Achievement] {
        var fresh: [Achievement] = []
        for a in Rewards.achievements where persistence.progress.unlocked[a.id] == nil && a.isMet(persistence.progress) {
            persistence.progress.unlocked[a.id] = Date()
            fresh.append(a)
        }
        for a in fresh {
            audio.play(.achievement)
            haptics.play(.achievement)
            speech.announce("Achievement unlocked: \(a.title). \(a.detail)")
        }
        return fresh
    }

    /// Called whenever an object is found or identified. Returns whether it was new.
    @discardableResult
    func celebrateDiscovery(_ o: CelestialObject, method: DiscoveryMethod) -> Bool {
        let isNew = persistence.recordDiscovery(o.id, method: method)
        noteActivity(o.id)
        if isNew {
            audio.play(SoundEffect.forDiscovery(o.kind))
            haptics.play(.discovery)
            speech.announce("New discovery added to your journal: \(o.spokenName).")
        }
        evaluate()
        return isNew
    }

    func noteLearned(_ o: CelestialObject, story: Bool) {
        if story { persistence.markStoryHeard(o.id) } else { persistence.markLearned(o.id) }
        noteActivity(o.id)
        evaluate()
    }

    private func noteActivity(_ id: String) {
        if Rewards.dailySuggestion().id == id { persistence.progress.dailyDone.insert(PersistenceManager.dayKey()) }
    }

    var dailyDone: Bool { persistence.progress.dailyDone.contains(PersistenceManager.dayKey()) }
}
