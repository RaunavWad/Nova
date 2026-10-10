//
//  GuidanceEngine.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation
import Combine
import CoreLocation
@preconcurrency import AVFoundation


@MainActor
final class GuidanceEngine: ObservableObject {

    enum State: Equatable {
        case idle, needsCalibration, locationProblem, targetBelowHorizon
        case searching, directional, aligned
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var separation: Double?
    @Published private(set) var summary: String = "Guidance is not running."
    @Published private(set) var target: CelestialObject?

    var onAligned: (@MainActor (CelestialObject) -> Void)?

    private let motion: MotionManager
    private let location: LocationManager
    private let speech: SpeechManager
    private let audio: AudioManager
    private let haptics: HapticsManager
    private let persistence: PersistenceManager

    private var task: Task<Void, Never>?
    private var targetPos: Horizontal?
    private var targetPosTime = Date.distantPast
    private var nextPulse = Date()
    private var alignedTicks = 0
    private var firedAligned = false
    private var lastWarning = Date.distantPast
    private var lowAccuracyAnnounced = false
    private var belowHorizonAnnounced = false

    init(motion: MotionManager, location: LocationManager, speech: SpeechManager, audio: AudioManager,
         haptics: HapticsManager, persistence: PersistenceManager) {
        self.motion = motion; self.location = location; self.speech = speech
        self.audio = audio; self.haptics = haptics; self.persistence = persistence
    }

    // MARK: Control

    func start(target: CelestialObject) {
        stop()
        self.target = target
        firedAligned = false; alignedTicks = 0; lowAccuracyAnnounced = false; belowHorizonAnnounced = false
        targetPos = nil; targetPosTime = .distantPast; nextPulse = Date()
        state = .searching
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
        audio.stopGuidance()
        state = .idle
        separation = nil
        summary = "Guidance is not running."
    }

    // MARK: Loop

    private func warn(_ text: String, summary s: String) {
        summary = s
        guard Date().timeIntervalSince(lastWarning) > 10 else { return }
        lastWarning = Date()
        haptics.play(.warning)
        audio.play(.warning)
        speech.speakGuidance(text, force: true)       // errors are always spoken, whatever the guidance style
    }

    private func tick() {
        guard let target else { return }
        let s = persistence.settings
        let now = Date()

        // 1. Location
        guard let coord = location.coordinate(demo: s.demoMode) else {
            state = .locationProblem; audio.stopGuidance()
            warn(location.isDenied ? "I can't find objects without your location. Please allow location access in the Settings app."
                                   : "Still waiting for your location.",
                 summary: location.statusDescription)
            return
        }

        // 2. Target position (cheap, but no need to recompute 10x per second)
        if now.timeIntervalSince(targetPosTime) > 1 || targetPos == nil {
            targetPos = AstronomyEngine.position(of: target, date: now, latitude: coord.latitude, longitude: coord.longitude)
            targetPosTime = now
        }
        guard let tp = targetPos else { return }
        if tp.altitude < 0 {
            state = .targetBelowHorizon; audio.stopGuidance()
            summary = "\(target.name) is below the horizon right now."
            if !belowHorizonAnnounced {
                belowHorizonAnnounced = true
                speech.speakGuidance("\(target.spokenName) is below the horizon right now, so it can't be found. Try another object.", force: true)
                haptics.play(.warning)
            }
            return
        }
        belowHorizonAnnounced = false

        // 3. Sensor reliability
        guard motion.isFresh, let p = motion.pointing, motion.quality >= .low else {
            state = .needsCalibration; audio.stopGuidance()
            warn("The compass needs calibration. Move your phone slowly in a figure eight, then try again. Or open Calibration from the Find screen.",
                 summary: "Compass not ready: \(motion.quality.spoken)")
            return
        }
        let directionalOK = motion.quality >= .medium

        // 4. Geometry
        let dAz = AstronomyEngine.norm180(tp.azimuth - p.azimuth)
        let dAlt = tp.altitude - p.altitude
        let sep = AstronomyEngine.separation(p, tp)
        separation = sep
        let threshold = max(4, motion.uncertainty * 0.7)

        // 5. Alignment (held briefly so jitter doesn't cause false positives)
        if sep <= threshold {
            alignedTicks += 1
        } else if sep > threshold * 1.6 {
            if state == .aligned { state = .searching }
            alignedTicks = 0
        }
        if alignedTicks >= 6 {
            if state != .aligned {
                state = .aligned
                haptics.play(.aligned)
                audio.play(.aligned)
                if !firedAligned { firedAligned = true; onAligned?(target) }
            }
            audio.updateGuidance(dAzimuth: 0, dAltitude: 0, separation: 0, aligned: true)
            summary = "You are pointing at \(target.name), within about \(Int(threshold.rounded())) degrees."
            return
        }

        // 6. Directional or distance-only cues
        state = directionalOK && sep <= 45 ? .directional : .searching
        audio.updateGuidance(dAzimuth: directionalOK ? dAz : 0, dAltitude: directionalOK ? dAlt : 0,
                             separation: sep, aligned: false)

        let interval = 0.35 + (1 - min(sep, 90) / 90) * 0.9          // calmer pulses as you close in
        if now >= nextPulse {
            nextPulse = now.addingTimeInterval(interval)
            if s.guidanceStyle != .speechOnly {
                if state == .directional {
                    if abs(dAz) >= abs(dAlt) { haptics.play(dAz > 0 ? .turnRight : .turnLeft) }
                    else { haptics.play(dAlt > 0 ? .tiltUp : .tiltDown) }
                } else {
                    haptics.play(.searching)
                }
            }
        }

        // 7. Speech (rate limited; "minimal" mode only speaks problems and the final celebration)
        if directionalOK {
            summary = "\(target.name) is \(ObjectMatcher.relativeDirection(dAzimuth: dAz, dAltitude: dAlt))."
            if s.verbosity != .minimal {
                speech.speakGuidance("Turn \(dAz > 0 ? "right" : "left") about \(max(5, Int(abs(dAz) / 5) * 5)) degrees and tilt \(dAlt > 0 ? "up" : "down") about \(max(5, Int(abs(dAlt) / 5) * 5)).")
            }
        } else {
            summary = "\(target.name) is about \(Int(sep.rounded())) degrees away. Compass accuracy is low, so I can't say which way."
            if !lowAccuracyAnnounced {
                lowAccuracyAnnounced = true
                speech.speakGuidance("Compass accuracy is low, so I can only tell you how close you are, not which way to turn. Move away from metal and electronics, or calibrate.", force: true)
            }
        }
    }
}
