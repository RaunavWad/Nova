//
//  AudioManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation
import AVFoundation
import Combine

enum SoundEffect {
    case star, planet, moon, deepSky, constellation, aligned, achievement, warning, confirm

    static func forDiscovery(_ kind: ObjectKind) -> SoundEffect {
        switch kind {
        case .star: return .star
        case .planet: return .planet
        case .moon: return .moon
        case .deepSky: return .deepSky
        case .constellation: return .constellation
        }
    }
}

// MARK: - Render state (touched from the audio thread; values are simple scalars, races are benign)

private final class PadState: @unchecked Sendable {
    var phases = [Double](repeating: 0, count: 10)
    var lfo = [Double](repeating: 0, count: 5)
    var gain: Float = 0
    var targetGain: Float = 0
    let freqs: [Double] = [110.0, 164.81, 220.0, 261.63, 329.63]   // open A-minor pad, original and synthesized

    func render(frames: Int, list: UnsafeMutableAudioBufferListPointer, sr: Double) {
        let twoPi = 2 * Double.pi
        for n in 0..<frames {
            gain += (targetGain - gain) * 0.00002           // ~1–2 second fades
            var l = 0.0, r = 0.0
            for k in 0..<5 {
                lfo[k] += twoPi * (0.03 + 0.017 * Double(k)) / sr
                if lfo[k] > twoPi { lfo[k] -= twoPi }
                let amp = 0.25 + 0.75 * (0.5 + 0.5 * sin(lfo[k]))
                phases[2 * k] += twoPi * freqs[k] / sr
                phases[2 * k + 1] += twoPi * freqs[k] * 1.0025 / sr
                if phases[2 * k] > twoPi { phases[2 * k] -= twoPi }
                if phases[2 * k + 1] > twoPi { phases[2 * k + 1] -= twoPi }
                l += amp * sin(phases[2 * k]); r += amp * sin(phases[2 * k + 1])
            }
            let g = Double(gain) * 0.07
            for (c, buf) in list.enumerated() {
                guard let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                p[n] = Float((c == 0 ? l : r) * g)
            }
        }
    }
}

private final class ToneState: @unchecked Sendable {
    var freq = 440.0, targetFreq = 440.0
    var gain: Float = 0, targetGain: Float = 0
    var pulseRate = 0.0              // Hz; 0 = steady tone
    var phase = 0.0, pulsePhase = 0.0

    func render(frames: Int, list: UnsafeMutableAudioBufferListPointer, sr: Double) {
        let twoPi = 2 * Double.pi
        for n in 0..<frames {
            freq += (targetFreq - freq) * 0.002
            gain += (targetGain - gain) * 0.003
            phase += twoPi * freq / sr
            if phase > twoPi { phase -= twoPi }
            var env = 1.0
            if pulseRate > 0 {
                pulsePhase += twoPi * pulseRate / sr
                if pulsePhase > twoPi { pulsePhase -= twoPi }
                let s = sin(pulsePhase); env = s > 0 ? s * s : 0
            }
            let v = Float((sin(phase) + 0.25 * sin(2 * phase)) * 0.5 * env) * gain
            for buf in list { buf.mData?.assumingMemoryBound(to: Float.self)[n] = v }
        }
    }
}

// MARK: - Manager

/// Original, synthesized audio only: no third-party music or samples, so there are no licensing issues.
/// Graph: pad -> ambienceMixer -> main;  effects player -> effectsMixer -> main;
///        guidance tone -> environment node (3D / HRTF) -> guidanceMixer -> main.
/// Speech is produced separately by AVSpeechSynthesizer (see SpeechManager) and ducks ambience + guidance.
@MainActor
final class AudioManager: ObservableObject {
    @Published private(set) var isPaused = false

    var settingsProvider: @MainActor () -> AppSettings = { AppSettings() }

    private let engine = AVAudioEngine()
    private let ambienceMixer = AVAudioMixerNode()
    private let effectsMixer = AVAudioMixerNode()
    private let guidanceMixer = AVAudioMixerNode()
    private let environment = AVAudioEnvironmentNode()
    private let effectsPlayer = AVAudioPlayerNode()
    private var padNode: AVAudioSourceNode?
    private var toneNode: AVAudioSourceNode?
    private let pad = PadState()
    private let tone = ToneState()
    private let effectFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var activeSFX: [AVAudioPlayer] = []     // bundled ElevenLabs-generated effects currently playing
    private var built = false
    private var ducked = false
    private var observers: [NSObjectProtocol] = []

    // MARK: Lifecycle

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        if !built { build() }
        startEngine()
        apply(settingsProvider())

        if observers.isEmpty {
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
                guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                Task { @MainActor in if self?.isPaused == false { self?.startEngine() } }
            })
            observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                Task { @MainActor in if self?.isPaused == false { self?.startEngine() } }
            })
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
        if engine.isRunning { effectsPlayer.play() }
    }

    private func build() {
        built = true
        var sr = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sr < 8000 { sr = 48000 }
        let stereo = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let mono = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let padState = pad, toneState = tone

        let padSrc = AVAudioSourceNode(format: stereo) { _, _, frames, abl -> OSStatus in
            padState.render(frames: Int(frames), list: UnsafeMutableAudioBufferListPointer(abl), sr: sr)
            return noErr
        }
        let toneSrc = AVAudioSourceNode(format: mono) { _, _, frames, abl -> OSStatus in
            toneState.render(frames: Int(frames), list: UnsafeMutableAudioBufferListPointer(abl), sr: sr)
            return noErr
        }
        padNode = padSrc; toneNode = toneSrc

        [ambienceMixer, effectsMixer, guidanceMixer, environment, effectsPlayer, padSrc, toneSrc].forEach { engine.attach($0) }
        engine.connect(padSrc, to: ambienceMixer, format: stereo)
        engine.connect(ambienceMixer, to: engine.mainMixerNode, format: stereo)
        engine.connect(effectsPlayer, to: effectsMixer, format: effectFormat)
        engine.connect(effectsMixer, to: engine.mainMixerNode, format: stereo)
        engine.connect(toneSrc, to: environment, format: mono)          // mono source so it can be spatialised
        engine.connect(environment, to: guidanceMixer, format: stereo)
        engine.connect(guidanceMixer, to: engine.mainMixerNode, format: stereo)
        environment.outputType = .auto
        toneSrc.renderingAlgorithm = .equalPowerPanning
        toneSrc.position = AVAudio3DPoint(x: 0, y: 0, z: -1)
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        buildEffects()
    }

    // MARK: Settings and controls

    func apply(_ s: AppSettings) {
        pad.targetGain = s.ambienceEnabled ? 1 : 0
        updateVolumes(s)
        toneNode?.renderingAlgorithm = s.spatialAudio ? .HRTFHQ : .equalPowerPanning
    }

    private func updateVolumes(_ s: AppSettings) {
        let duck: Float = ducked ? 0.25 : 1
        ambienceMixer.outputVolume = Float(s.ambienceVolume) * duck
        effectsMixer.outputVolume = s.effectsEnabled ? Float(s.effectsVolume) : 0
        guidanceMixer.outputVolume = s.guidanceTone ? Float(max(0.3, s.effectsVolume)) * duck : 0
    }

    /// Called by SpeechManager so music and guidance tone get out of the way of narration.
    func setNarrationActive(_ active: Bool) {
        ducked = active
        updateVolumes(settingsProvider())
    }

    func pause() { isPaused = true; engine.pause() }
    func resume() { isPaused = false; startEngine() }

    func stopAllSounds() {
        tone.targetGain = 0
        effectsPlayer.stop(); effectsPlayer.play()
        activeSFX.forEach { $0.stop() }; activeSFX.removeAll()
    }

    // MARK: Guidance tone

    /// dAz: degrees to turn right (+) or left (-), dAlt: degrees to tilt up (+) or down (-).
    /// Spatial position puts the tone where the target is relative to the pointing direction;
    /// pitch rises when the target is higher (a second, headphone-independent cue).
    func updateGuidance(dAzimuth: Double, dAltitude: Double, separation: Double, aligned: Bool) {
        guard settingsProvider().guidanceTone, engine.isRunning else { tone.targetGain = 0; return }
        let az = AstronomyEngine.rad(max(-180, min(180, dAzimuth)))
        let el = AstronomyEngine.rad(max(-60, min(60, dAltitude)))
        toneNode?.position = AVAudio3DPoint(x: Float(sin(az) * cos(el)), y: Float(sin(el)), z: Float(-cos(az) * cos(el)))
        if aligned {
            tone.targetFreq = 523.25; tone.pulseRate = 0; tone.targetGain = 0.35
        } else {
            let semis = max(-9.0, min(9.0, dAltitude / 45 * 9))
            tone.targetFreq = 440 * pow(2, semis / 12)
            tone.pulseRate = 2.5
            tone.targetGain = Float(0.15 + 0.2 * max(0, 1 - separation / 60))
        }
    }

    func stopGuidance() { tone.targetGain = 0 }

    // MARK: Effects

    func play(_ effect: SoundEffect) {
        guard settingsProvider().effectsEnabled, !isPaused else { return }
        // Prefer a bundled, ElevenLabs-generated file (Resources/Sounds/sfx_<name>.mp3); otherwise the synthesized fallback.
        if let url = Bundle.main.url(forResource: "sfx_\(key(effect))", withExtension: "mp3"),
           let p = try? AVAudioPlayer(contentsOf: url) {
            activeSFX.removeAll { !$0.isPlaying }
            p.volume = Float(settingsProvider().effectsVolume)
            p.prepareToPlay(); p.play()
            activeSFX.append(p)
            return
        }
        guard let buf = buffers[key(effect)] else { return }
        if !engine.isRunning { startEngine() }
        effectsPlayer.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        if !effectsPlayer.isPlaying { effectsPlayer.play() }
    }

    private func key(_ e: SoundEffect) -> String { String(describing: e) }

    private struct Note { var f: Double; var t: Double; var d: Double; var a: Double = 1 }

    private func make(_ notes: [Note], length: Double) -> AVAudioPCMBuffer {
        let sr = effectFormat.sampleRate
        let frames = AVAudioFrameCount(length * sr)
        let buf = AVAudioPCMBuffer(pcmFormat: effectFormat, frameCapacity: frames)!
        buf.frameLength = frames
        let p = buf.floatChannelData![0]
        for i in 0..<Int(frames) { p[i] = 0 }
        for n in notes {
            let start = Int(n.t * sr), count = Int(n.d * sr)
            for i in 0..<count where start + i < Int(frames) {
                let t = Double(i) / sr
                let attack = min(1, t / 0.008)
                let env = attack * exp(-t / (n.d / 4))
                let s = sin(2 * .pi * n.f * t) + 0.3 * sin(4 * .pi * n.f * t) + 0.1 * sin(6 * .pi * n.f * t)
                p[start + i] += Float(s * env * n.a * 0.25)
            }
        }
        var peak: Float = 0.0001
        for i in 0..<Int(frames) { peak = max(peak, abs(p[i])) }
        let k = min(1, 0.8 / peak)
        for i in 0..<Int(frames) { p[i] *= k }
        return buf
    }

    private func buildEffects() {
        buffers[key(.star)] = make([Note(f: 1318.5, t: 0, d: 0.9), Note(f: 1760, t: 0.12, d: 0.9, a: 0.8)], length: 1.2)
        buffers[key(.planet)] = make([Note(f: 392, t: 0, d: 1.0), Note(f: 523.25, t: 0.15, d: 1.0), Note(f: 659.25, t: 0.3, d: 1.2)], length: 1.6)
        buffers[key(.moon)] = make([Note(f: 196, t: 0, d: 1.6), Note(f: 261.63, t: 0, d: 1.6, a: 0.8), Note(f: 329.63, t: 0.05, d: 1.6, a: 0.6)], length: 1.9)
        buffers[key(.deepSky)] = make([880, 1108.7, 1318.5, 1760, 2217.5].enumerated().map { Note(f: $1, t: Double($0) * 0.1, d: 1.5, a: 0.7) }, length: 2.2)
        buffers[key(.constellation)] = make([523.25, 659.25, 783.99, 1046.5].enumerated().map { Note(f: $1, t: Double($0) * 0.12, d: 0.9) }, length: 1.6)
        buffers[key(.aligned)] = make([Note(f: 784, t: 0, d: 0.3), Note(f: 784, t: 0.2, d: 0.3), Note(f: 1175, t: 0.2, d: 0.5, a: 0.6)], length: 0.8)
        buffers[key(.achievement)] = make([523.25, 659.25, 783.99, 1046.5, 1318.5].enumerated().map { Note(f: $1, t: Double($0) * 0.09, d: 1.4, a: 0.8) }, length: 2.0)
        buffers[key(.warning)] = make([Note(f: 220, t: 0, d: 0.3), Note(f: 196, t: 0.25, d: 0.4)], length: 0.8)
        buffers[key(.confirm)] = make([Note(f: 880, t: 0, d: 0.14)], length: 0.25)
    }
}
