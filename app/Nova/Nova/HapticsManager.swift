//
//  HapticsManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Combine
import Foundation
import CoreHaptics
import UIKit

/// The Nova haptic language. Every pattern has a spoken/text equivalent elsewhere in the app;
/// haptics are never the only channel for errors, achievements or instructions.
enum HapticPattern: String, CaseIterable {
    case select          // one short tick: a control was activated
    case searching       // one soft, medium pulse: keep sweeping (target is far or direction unreliable)
    case turnRight       // one firm tap: turn right
    case turnLeft        // two quick light taps: turn left
    case tiltUp          // rising buzz: raise the phone
    case tiltDown        // falling buzz: lower the phone
    case aligned         // distinct double thump: you are on target
    case discovery       // celebratory rising flurry: new discovery
    case achievement     // longer flourish: achievement unlocked
    case warning         // three sharp, dull taps: calibration or location problem

    var meaning: String {
        switch self {
        case .select: return "Short tick: a button was activated."
        case .searching: return "Single soft pulse, repeated: keep searching. Slower pulses mean you are closer."
        case .turnRight: return "One firm tap: the target is to your right."
        case .turnLeft: return "Two quick light taps: the target is to your left."
        case .tiltUp: return "Rising buzz: the target is higher; tilt the phone up."
        case .tiltDown: return "Falling buzz: the target is lower; tilt the phone down."
        case .aligned: return "Strong double thump: you are pointing at the target."
        case .discovery: return "Rising flurry of taps: a new discovery."
        case .achievement: return "Long flourish: an achievement was unlocked."
        case .warning: return "Three sharp, dull taps: a calibration or location problem needs attention."
        }
    }
}

@MainActor
final class HapticsManager: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()   // explicit, so conformance never depends on synthesis
    private var engine: CHHapticEngine?
    private let supportsCore = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    var settingsProvider: @MainActor () -> AppSettings = { AppSettings() }

    var isCoreHapticsSupported: Bool { supportsCore }

    init() { prepare() }

    private func prepare() {
        guard supportsCore else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            e.resetHandler = { [weak self] in try? self?.engine?.start() }
            e.stoppedHandler = { _ in }
            try e.start()
            engine = e
        } catch { engine = nil }
    }

    private var lastSelectTime = Date.distantPast

    func play(_ pattern: HapticPattern) {
        let s = settingsProvider()
        guard s.hapticsEnabled else { return }
        // Taps can come from several places at once (the button style and its action); play only one.
        if pattern == .select {
            let now = Date()
            guard now.timeIntervalSince(lastSelectTime) > 0.09 else { return }
            lastSelectTime = now
        }
        if supportsCore, playCore(pattern, intensity: Float(s.hapticIntensity)) { return }
        playFallback(pattern)
    }

    // MARK: Core Haptics
    private func tap(_ t: TimeInterval, _ intensity: Float, _ sharp: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)],
                      relativeTime: t)
    }
    private func buzz(_ t: TimeInterval, _ dur: TimeInterval, _ intensity: Float, _ sharp: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                                   CHHapticEventParameter(parameterID: .hapticSharpness, value: sharp)],
                      relativeTime: t, duration: dur)
    }

    private func playCore(_ p: HapticPattern, intensity k: Float) -> Bool {
        if engine == nil { prepare() }
        guard let engine else { return false }
        func i(_ v: Float) -> Float { max(0.05, min(1, v * k)) }
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        switch p {
        case .select: events = [tap(0, i(0.6), 0.8)]
        case .searching: events = [tap(0, i(0.45), 0.2), buzz(0, 0.08, i(0.3), 0.1)]
        case .turnRight: events = [tap(0, i(1.0), 0.9)]
        case .turnLeft: events = [tap(0, i(0.5), 0.4), tap(0.12, i(0.5), 0.4)]
        case .tiltUp:
            events = [buzz(0, 0.25, i(0.8), 0.5)]
            curves = [CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                        controlPoints: [.init(relativeTime: 0, value: 0.2), .init(relativeTime: 0.25, value: 1.0)], relativeTime: 0)]
        case .tiltDown:
            events = [buzz(0, 0.25, i(0.8), 0.5)]
            curves = [CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                        controlPoints: [.init(relativeTime: 0, value: 1.0), .init(relativeTime: 0.25, value: 0.2)], relativeTime: 0)]
        case .aligned: events = [tap(0, i(1.0), 0.6), tap(0.18, i(1.0), 0.6), buzz(0.18, 0.2, i(0.5), 0.3)]
        case .discovery: events = (0..<6).map { tap(Double($0) * 0.08, i(0.4 + Float($0) * 0.12), 0.3 + Float($0) * 0.12) }
        case .achievement:
            events = (0..<5).map { tap(Double($0) * 0.1, i(0.6 + Float($0) * 0.08), 0.5) } + [buzz(0.5, 0.45, i(0.7), 0.4)]
        case .warning: events = [tap(0, i(0.9), 0.1), tap(0.18, i(0.9), 0.1), tap(0.36, i(0.9), 0.1)]
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch { return false }
    }

    // MARK: UIKit fallback (strength is fixed by the system on these devices)
    private func playFallback(_ p: HapticPattern) {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        let notify = UINotificationFeedbackGenerator()
        switch p {
        case .select: UISelectionFeedbackGenerator().selectionChanged()
        case .searching: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .turnRight: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .turnLeft:
            let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { g.impactOccurred() }
        case .tiltUp: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .tiltDown: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
        case .aligned:
            impact.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { impact.impactOccurred() }
        case .discovery, .achievement: notify.notificationOccurred(.success)
        case .warning: notify.notificationOccurred(.warning)
        }
    }
}
