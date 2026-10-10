//
//  FindObjectView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI

extension CelestialObject {
    var title: String { name.prefix(1).uppercased() + name.dropFirst() }
}

struct FindObjectView: View {
    var initialTarget: CelestialObject? = nil

    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject var guidance: GuidanceEngine
    @EnvironmentObject var achievements: AchievementManager
    @EnvironmentObject var haptics: HapticsManager

    @State private var selected: CelestialObject?
    @State private var didAutoStart = false
    @State private var showCalibration = false
    @State private var rows: [(object: CelestialObject, text: String)] = []

    var body: some View {
        Screen(title: "Find an Object") {
            if let sel = selected { guidanceSection(sel) } else { chooser }
        }
        .sheet(isPresented: $showCalibration) {
            NavigationStack {
                CalibrationView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showCalibration = false } } }
            }
            .environmentObject(persistence).environmentObject(location).environmentObject(motion)
            .environmentObject(speech).environmentObject(audio).environmentObject(guidance).environmentObject(haptics)
        }
        .onAppear {
            location.start()
            refresh()
            if let t = initialTarget, !didAutoStart { didAutoStart = true; begin(t) }
        }
        .onDisappear {
            guidance.stop(); motion.stop(); speech.stop(); audio.stopGuidance()
            selected = nil
        }
    }

    // MARK: Choosing

    private var chooser: some View {
        Group {
            Text("Choose what to find").sectionHeader()
            Text("Only objects that can be located with your phone's sensors are listed. Objects below the horizon can't be found right now.")
                .font(AppFont.style(.subheadline))
            ForEach(rows, id: \.object.id) { row in
                Button { begin(row.object) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.object.title)
                        Text(row.text).font(AppFont.style(.subheadline))
                    }
                }
                .buttonStyle(BigButtonStyle(prominent: false))
                .accessibilityElement(children: .combine)
                .accessibilityHint("Starts guidance to this object")
            }
            if rows.isEmpty {
                Panel { Text(location.statusDescription) }
            }
            DemoControls()
        }
    }

    private func refresh() {
        guard let c = location.coordinate(demo: persistence.settings.demoMode) else { rows = []; return }
        let now = Date()
        rows = Catalog.locatable.map { o in
            guard let p = AstronomyEngine.position(of: o, date: now, latitude: c.latitude, longitude: c.longitude) else { return (o, "") }
            return (o, p.altitude < 0 ? "Below the horizon right now." : "Currently \(AstronomyEngine.describeLocation(p)).")
        }
    }

    // MARK: Guiding

    private func guidanceSection(_ sel: CelestialObject) -> some View {
        let pos: Horizontal? = location.coordinate(demo: persistence.settings.demoMode).flatMap {
            AstronomyEngine.position(of: sel, date: Date(), latitude: $0.latitude, longitude: $0.longitude)
        }
        return Group {
            Panel {
                Text("Finding \(sel.name)").sectionHeader()
                Text("Hold the phone with its back toward the sky and move it slowly. Pulses guide you; a double thump and a steady tone mean you are on target.")
                if let pos { Text("It is currently \(pos.altitude < 0 ? "below the horizon" : AstronomyEngine.describeLocation(pos)).").font(AppFont.style(.subheadline)) }
                // Live status changes ten times a second, so it is hidden from VoiceOver; use the button below instead.
                Text("Live status: \(guidance.summary)").font(AppFont.style(.footnote)).foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
            }

            AppButton(title: "What's my status?", systemImage: "waveform", hint: "Speaks how far you are from the target and which way to turn") {
                speech.speak(guidance.summary)
            }

            if guidance.state == .needsCalibration {
                Panel {
                    Label("The compass needs calibration", systemImage: "exclamationmark.triangle").font(AppFont.style(.headline, .semibold))
                    Text("Move your phone slowly in a figure eight, away from metal and magnets.")
                }
            }
            if guidance.state == .aligned {
                Panel {
                    Label("You found \(sel.name)!", systemImage: "sparkles").font(AppFont.style(.headline, .semibold)).foregroundStyle(Theme.violet)
                    NavigationLink { ObjectDetailView(object: sel) } label: { Label("Tell me more", systemImage: "book") }
                        .buttonStyle(BigButtonStyle())
                }
            }

            DemoControls(target: pos)

            AppButton(title: "Calibrate compass", systemImage: "safari", prominent: false) { showCalibration = true }
            AppButton(title: "Stop and choose another object", systemImage: "arrow.uturn.backward", prominent: false) {
                guidance.stop(); speech.stop(); selected = nil; refresh()
            }
            SpeechControls()
        }
    }

    private func begin(_ o: CelestialObject) {
        selected = o
        motion.start()
        guidance.onAligned = { [weak achievements, weak speech] obj in
            speech?.speakGuidance("You found \(obj.spokenName)! \(obj.short) Tap Tell me more to learn about it.", force: true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                achievements?.celebrateDiscovery(obj, method: .found)
            }
        }
        guidance.start(target: o)
        speech.speak("Finding \(o.spokenName). Hold your phone with its back toward the sky and move it slowly. Pulses get calmer as you get closer. A double thump means you're on target. Stand still on safe ground.")
    }
}

// MARK: - Calibration

struct CalibrationView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var guidance: GuidanceEngine
    @EnvironmentObject var haptics: HapticsManager

    private static let guide = "To calibrate the compass: stand away from cars, metal furniture, magnets and speakers. Hold your phone in front of you and slowly draw a figure eight in the air, tilting and rotating it, for about ten seconds. I'll tell you when the compass accuracy improves."

    var body: some View {
        Screen(title: "Calibrate Compass") {
            Panel {
                Text("Compass status").sectionHeader()
                Text(motion.quality.spoken)
                Text(motion.usingTrueNorth ? "Using true north from your location." : "Using magnetic north. Allow location access for true north.")
                    .font(AppFont.style(.subheadline))
                Text(motion.statusText).font(AppFont.style(.subheadline))
            }.accessibilityElement(children: .combine)

            AppButton(title: "Start spoken calibration guide", systemImage: "figure.walk.motion") {
                motion.start(); speech.narrate(Self.guide)
            }
            AppButton(title: "Check compass accuracy now", systemImage: "checkmark.circle", prominent: false) {
                if !motion.isRunning { motion.start() }
                speech.speak("\(motion.quality.spoken) \(motion.quality >= .medium ? "That is good enough for guidance." : "Try the figure eight movement again.")")
            }

            Panel {
                Text("Optional heading adjustment").sectionHeader()
                Text("Phone compasses can be a few degrees off, especially indoors or near metal. If a sighted helper can confirm a direction, you can correct the compass. Current adjustment: \(Int(persistence.settings.azimuthOffset.rounded())) degrees.")
                    .font(AppFont.style(.subheadline))
                if persistence.settings.demoMode {
                    Text("Not available in Demo mode.").foregroundStyle(Theme.violet)
                }
            }
            AppButton(title: "Hold the phone level, facing true north, then tap", systemImage: "location.north.line", prominent: false) {
                guard !persistence.settings.demoMode else { return }
                motion.calibrate(toKnownAzimuth: 0)
                speech.speak("Adjusted. The compass was off by \(Int(abs(persistence.settings.azimuthOffset).rounded())) degrees.")
            }
            AppButton(title: "Use the Moon as a reference", systemImage: "moon", prominent: false,
                      hint: "A sighted helper aims the back of the phone at the Moon first") {
                guard !persistence.settings.demoMode, let c = location.coordinate(demo: false),
                      let moon = Catalog.object(id: "moon"),
                      let p = AstronomyEngine.position(of: moon, date: Date(), latitude: c.latitude, longitude: c.longitude) else {
                    speech.speak("I need a real location to do that."); return
                }
                guard p.altitude > 5 else { speech.speak("The Moon is not above the horizon right now."); return }
                motion.calibrate(toKnownAzimuth: p.azimuth)
                speech.speak("Adjusted using the Moon. The compass was off by \(Int(abs(persistence.settings.azimuthOffset).rounded())) degrees.")
            }
            AppButton(title: "Reset adjustment", systemImage: "arrow.counterclockwise", prominent: false) {
                persistence.settings.azimuthOffset = 0
                speech.speak("Compass adjustment reset.")
            }
            SpeechControls()
        }
        .onAppear {
            location.start()
            motion.start()
            speech.narrate(Self.guide)
        }
        .onDisappear { if guidance.state == .idle { motion.stop() } }
        .onChange(of: motion.quality) { old, new in
            guard old != new, new != .unavailable else { return }
            speech.announce(new >= .medium ? "\(new.spoken) Calibration looks good." : new.spoken)
            haptics.play(new >= .medium ? .aligned : .warning)
        }
    }
}
