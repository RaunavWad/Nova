//
//  PersistenceManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation
import Combine


enum Verbosity: String, Codable, CaseIterable, Identifiable {
    case minimal, normal, detailed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .minimal: return "Minimal speech"
        case .normal: return "Normal"
        case .detailed: return "Detailed"
        }
    }
}

enum GuidanceStyle: String, Codable, CaseIterable, Identifiable {
    case hapticsAndSpeech, hapticsOnly, speechOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hapticsAndSpeech: return "Haptics and speech"
        case .hapticsOnly: return "Haptics only"
        case .speechOnly: return "Speech only"
        }
    }
}

enum PointingMode: String, Codable, CaseIterable, Identifiable {
    case backOfPhone, topEdge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .backOfPhone: return "Back of the phone (like a camera)"
        case .topEdge: return "Top edge of the phone (like a wand)"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var speechRate: Float = 0.5
    var verbosity: Verbosity = .normal
    var useVoiceOverAnnouncements = true
    var premiumVoice = true
    var guidanceStyle: GuidanceStyle = .hapticsAndSpeech
    var guidanceSpeechInterval: Double = 8
    var hapticsEnabled = true
    var hapticIntensity: Double = 0.8
    var narrationVolume: Double = 1.0
    var ambienceEnabled = false
    var ambienceVolume: Double = 0.35
    var effectsEnabled = true
    var effectsVolume: Double = 0.7
    var guidanceTone = true
    var spatialAudio = true
    var pointingMode: PointingMode = .backOfPhone
    var demoMode = false
    var hasHeardIntro = false
    var azimuthOffset: Double = 0
    var greetingEnabled: Bool? = nil
    var speaksGreeting: Bool { greetingEnabled ?? true }
}


enum DiscoveryMethod: String, Codable { case found, identified }

struct DiscoveryRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var objectID: String
    var date: Date
    var method: DiscoveryMethod
    var demo: Bool
}

struct UserProgress: Codable, Equatable {
    var discoveries: [DiscoveryRecord] = []
    var learned: Set<String> = []
    var storiesHeard: Set<String> = []
    var usageDays: Set<String> = []
    var unlocked: [String: Date] = [:]
    var dailyDone: Set<String> = []

    var discoveredIDs: Set<String> { Set(discoveries.map(\.objectID)) }
}


@MainActor
final class PersistenceManager: ObservableObject {
    @Published var settings: AppSettings { didSet { if settings != oldValue { save(settings, name: "settings.json") } } }
    @Published var progress: UserProgress { didSet { if progress != oldValue { save(progress, name: "progress.json") } } }

    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Nova", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        dir = d
        settings = PersistenceManager.load(AppSettings.self, from: d.appendingPathComponent("settings.json")) ?? AppSettings()
        progress = PersistenceManager.load(UserProgress.self, from: d.appendingPathComponent("progress.json")) ?? UserProgress()
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, name: String) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    func markUsedToday() { progress.usageDays.insert(Self.dayKey()) }

    @discardableResult
    func recordDiscovery(_ objectID: String, method: DiscoveryMethod) -> Bool {
        let isNew = !progress.discoveredIDs.contains(objectID)
        if isNew {
            progress.discoveries.append(DiscoveryRecord(objectID: objectID, date: Date(), method: method, demo: settings.demoMode))
        }
        return isNew
    }

    func markLearned(_ id: String) { progress.learned.insert(id) }
    func markStoryHeard(_ id: String) { progress.storiesHeard.insert(id); progress.learned.insert(id) }

    func resetProgress() { progress = UserProgress() }
}
