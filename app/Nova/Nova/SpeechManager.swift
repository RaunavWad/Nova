import Foundation
import AVFoundation
import UIKit

/// Spoken output. Uses AVSpeechSynthesizer for narration. If VoiceOver is running and the user prefers it,
/// short status messages are posted as VoiceOver announcements instead so the two voices never talk over each other.
@MainActor
final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var lastSpoken: String = ""

    var settingsProvider: @MainActor () -> AppSettings = { AppSettings() }
    weak var audio: AudioManager?

    private let synth = AVSpeechSynthesizer()
    private var lastGuidanceTime = Date.distantPast
    private var queue: [String] = []
    private var player: AVAudioPlayer?              // premium (ElevenLabs) narration
    private var narrationTask: Task<Void, Never>?

    var premiumAvailable: Bool { ElevenLabsClient.shared.isConfigured }

    override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: Speaking

    /// Speak a message. `interrupt` replaces whatever is being said; otherwise it is queued.
    func speak(_ text: String, interrupt: Bool = true, remember: Bool = true) {
        let s = settingsProvider()
        if remember { lastSpoken = text }
        if interrupt { cancelPremium(); synth.stopSpeaking(at: .immediate); queue.removeAll() }
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceMinimumSpeechRate + Float(s.speechRate) * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
        u.volume = Float(s.narrationVolume)
        u.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        u.preUtteranceDelay = 0.05
        synth.speak(u)
    }

    /// Short status line for VoiceOver users; falls back to narration otherwise.
    func announce(_ text: String) {
        let s = settingsProvider()
        lastSpoken = text
        if UIAccessibility.isVoiceOverRunning && s.useVoiceOverAnnouncements {
            UIAccessibility.post(notification: .announcement, argument: text)
        } else {
            speak(text, interrupt: false, remember: false)
        }
    }

    /// Longer narration (descriptions, results, greeting). Order of preference:
    ///  1. VoiceOver announcement, when VoiceOver is on and the user prefers it;
    ///  2. the premium ElevenLabs voice, when configured and switched on (cached, so repeats are instant and work offline);
    ///  3. the built-in iPhone voice, which is also the fallback if the premium voice is slow, offline or errors.
    func narrate(_ text: String) {
        lastSpoken = text
        let s = settingsProvider()
        if UIAccessibility.isVoiceOverRunning && s.useVoiceOverAnnouncements {
            UIAccessibility.post(notification: .announcement, argument: text)
            return
        }
        guard s.premiumVoice, premiumAvailable else { speak(text, interrupt: true, remember: false); return }
        cancelPremium()
        synth.stopSpeaking(at: .immediate)
        narrationTask = Task { [weak self] in
            do {
                let data = try await ElevenLabsClient.shared.speech(for: text)
                guard !Task.isCancelled, let self else { return }
                self.playPremium(data, fallbackText: text)
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.speak(text, interrupt: true, remember: false)
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
            p.rate = Float(0.7 + 0.6 * s.speechRate)      // speech-speed setting: 0.5 = normal speed
            p.prepareToPlay()
            player = p
            isPaused = false
            isSpeaking = true
            audio?.setNarrationActive(true)
            p.play()
        } catch {
            speak(fallbackText, interrupt: true, remember: false)
        }
    }

    private func cancelPremium() {
        narrationTask?.cancel(); narrationTask = nil
        player?.stop(); player = nil
    }

    /// Rate-limited speech for live guidance so users are never flooded.
    func speakGuidance(_ text: String, force: Bool = false) {
        let s = settingsProvider()
        guard s.guidanceStyle != .hapticsOnly || force else { return }   // forced = problems/celebrations, always spoken
        guard force || Date().timeIntervalSince(lastGuidanceTime) >= s.guidanceSpeechInterval else { return }
        lastGuidanceTime = Date()
        // Never interrupt a message that is already being spoken (unless forced).
        if (synth.isSpeaking || player?.isPlaying == true) && !force { return }
        speak(text, interrupt: force, remember: false)
    }

    func repeatLast() { if !lastSpoken.isEmpty { narrate(lastSpoken) } }

    func stop() {
        cancelPremium()
        synth.stopSpeaking(at: .immediate); queue.removeAll()
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

    // MARK: Descriptions

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

    // MARK: AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            if !self.synth.isSpeaking { self.isSpeaking = false; self.isPaused = false; self.audio?.setNarrationActive(false) }
        }
    }

    // MARK: AVSpeechSynthesizerDelegate
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true; self.audio?.setNarrationActive(true) }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synth.isSpeaking { self.isSpeaking = false; self.audio?.setNarrationActive(false) }
        }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synth.isSpeaking { self.isSpeaking = false; self.audio?.setNarrationActive(false) }
        }
    }
}
