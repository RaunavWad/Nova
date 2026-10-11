//
//  SpeechManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Combine
import Foundation
@preconcurrency import AVFoundation
import UIKit

@MainActor
final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    let objectWillChange = ObservableObjectPublisher()
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var lastSpoken: String = ""
    @Published private(set) var premiumStatus: String? = nil

    var settingsProvider: @MainActor () -> AppSettings = { AppSettings() }
    weak var audio: AudioManager?

    private let synth = AVSpeechSynthesizer()
    private var lastGuidanceTime = Date.distantPast
    private var pending: [String] = []             
    private var player: AVAudioPlayer?
    private var narrationTask: Task<Void, Never>?

    var premiumAvailable: Bool { ElevenLabsClient.shared.isConfigured }
    private var usePremium: Bool { settingsProvider().premiumVoice && premiumAvailable }
    private var isBusy: Bool { synth.isSpeaking || player?.isPlaying == true || narrationTask != nil }

    override init() {
        super.init()
        synth.delegate = self
    }

   
    func speak(_ text: String, interrupt: Bool = true, remember: Bool = true) {
        if remember { lastSpoken = text }
        guard usePremium else { speakSystem(text, interrupt: interrupt); return }
        if interrupt {
            pending.removeAll()
            startPremium(text)
        } else if isBusy {
            pending.append(text)
        } else {
            startPremium(text)
        }
    }

    func announce(_ text: String) {
        let s = settingsProvider()
        lastSpoken = text
        if UIAccessibility.isVoiceOverRunning && s.useVoiceOverAnnouncements {
            UIAccessibility.post(notification: .announcement, argument: text)
        } else {
            speak(text, interrupt: false, remember: false)
        }
    }

    func narrate(_ text: String) {
        lastSpoken = text
        let s = settingsProvider()
        if UIAccessibility.isVoiceOverRunning && s.useVoiceOverAnnouncements {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        speak(text, interrupt: true, remember: false)
    }

    func checkPremium() async {
        premiumStatus = "Checking..."
        let result = await ElevenLabsClient.shared.check()
        premiumStatus = result
        if result == "Premium voice is working." { narrate("Nova premium voice is working.") }
    }


    private func speakSystem(_ text: String, interrupt: Bool) {
        let s = settingsProvider()
        if interrupt { cancelPremium(); pending.removeAll(); synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceMinimumSpeechRate + Float(s.speechRate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
        u.volume = Float(s.narrationVolume)
        u.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        u.preUtteranceDelay = 0.05
        synth.speak(u)
    }

// this is the nice elevenlabs voice :D!!
    
    private func startPremium(_ text: String) {
        cancelPremium()
        synth.stopSpeaking(at: .immediate)
        narrationTask = Task { [weak self] in
            do {
                let data = try await ElevenLabsClient.shared.speech(for: text)
                guard !Task.isCancelled, let self else { return }
                self.narrationTask = nil
                self.playPremium(data, fallbackText: text)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.narrationTask = nil
                self.premiumStatus = ElevenLabsClient.describe(error)
                self.speakSystem(text, interrupt: true)
            }
        }
    }

    private func playPremium(_ data: Data, fallbackText: String) {
        do {
            let s = settingsProvider()
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.volume = Float(s.narrationVolume)
            p.enableRate = true
            p.rate = Float(0.7 + 0.6 * s.speechRate)
            p.prepareToPlay()
            player = p
            isPaused = false
            isSpeaking = true
            audio?.setNarrationActive(true)
            p.play()
            premiumStatus = "Premium voice is working."
        } catch {
            speakSystem(fallbackText, interrupt: true)
        }
    }

    private func cancelPremium() {
        narrationTask?.cancel(); narrationTask = nil
        player?.stop(); player = nil
    }

    func speakGuidance(_ text: String, force: Bool = false) {
        let s = settingsProvider()
        guard s.guidanceStyle != .hapticsOnly || force else { return }
        guard force || Date().timeIntervalSince(lastGuidanceTime) >= s.guidanceSpeechInterval else { return }
        lastGuidanceTime = Date()
        if isBusy && !force { return }
        if usePremium {
            if ElevenLabsClient.shared.isCached(text) {
                speak(text, interrupt: force, remember: false)
            } else {
                speakSystem(text, interrupt: force)
                Task { await ElevenLabsClient.shared.prefetch(text) }
            }
        } else {
            speakSystem(text, interrupt: force)
        }
    }

    func repeatLast() { if !lastSpoken.isEmpty { narrate(lastSpoken) } }

    func stop() {
        cancelPremium()
        pending.removeAll()
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false; isPaused = false
        audio?.setNarrationActive(false)
    }

    func pause() {
        if let player, player.isPlaying { player.pause(); isPaused = true }
        else if synth.pauseSpeaking(at: .word) { isPaused = true }
    }
    func resume() {
        if let player, isPaused { player.play(); isPaused = false }
        else if synth.continueSpeaking() { isPaused = false }
    }


    func spokenName(_ o: CelestialObject) -> String { o.spokenName }

    func shortDescription(of o: CelestialObject, date: Date = Date()) -> String {
        var t = "\(o.spokenName). A \(o.kind.label). \(o.short)"
        if o.kind == .moon {
            let p = AstronomyEngine.moonPhase(date: date)
            t += " Tonight it is a \(p.name), about \(Int((p.fraction * 100).rounded())) percent lit."
        }
        if settingsProvider().verbosity != .minimal { t += " It is \(o.distance)." }
        return t
    }

    func deeperDescription(of o: CelestialObject) -> String {
        var t = o.deeper
        if settingsProvider().verbosity == .detailed { t += " Did you know? \(o.didYouKnow)" }
        return t
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            if !self.pending.isEmpty { self.startPremium(self.pending.removeFirst()); return }
            if !self.synth.isSpeaking { self.isSpeaking = false; self.isPaused = false; self.audio?.setNarrationActive(false) }
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true; self.audio?.setNarrationActive(true) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synth.isSpeaking && self.player == nil { self.isSpeaking = false; self.audio?.setNarrationActive(false) }
        }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synth.isSpeaking && self.player == nil { self.isSpeaking = false; self.audio?.setNarrationActive(false) }
        }
    }
}
