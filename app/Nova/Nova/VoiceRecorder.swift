//
//  VoiceRecorder.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Combine
import Foundation
@preconcurrency import AVFoundation


@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    enum Failure: LocalizedError {
        case missingUsageText, denied, cannotRecord
        var errorDescription: String? {
            switch self {
            case .missingUsageText:
                return "The microphone can't be used because the app is missing its microphone permission text. In Xcode, open the Nova target, Build Settings, and set Privacy - Microphone Usage Description."
            case .denied:
                return "Microphone access is off. Open the iPhone Settings app, then Nova, and turn on Microphone."
            case .cannotRecord:
                return "I couldn't start the microphone. Check that no other app is using it."
            }
        }
    }

    var onAutoStop: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var heardSpeech = false
    private var silentTicks = 0
    private var ticks = 0
    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("nova-question.m4a")

    static var hasUsageText: Bool { Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil }

    func requestPermission() async throws {
        guard Self.hasUsageText else { throw Failure.missingUsageText }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return
        case .undetermined:
            if await AVAudioApplication.requestRecordPermission() { return }
            throw Failure.denied
        default: throw Failure.denied
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        guard r.record() else { throw Failure.cannotRecord }
        recorder = r
        heardSpeech = false; silentTicks = 0; ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    @discardableResult
    func stop() -> URL? {
        timer?.invalidate(); timer = nil
        let had = recorder != nil
        recorder?.stop(); recorder = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        return had ? url : nil
    }

    func discard() { try? FileManager.default.removeItem(at: url) }

    private func tick() {
        guard let r = recorder else { return }
        r.updateMeters()
        ticks += 1
        let level = r.averagePower(forChannel: 0)
        if level > -38 { heardSpeech = true; silentTicks = 0 } else if heardSpeech { silentTicks += 1 }
     
        if (heardSpeech && silentTicks >= 12) || (!heardSpeech && ticks >= 40) || ticks >= 200 { onAutoStop?() }
    }
}
