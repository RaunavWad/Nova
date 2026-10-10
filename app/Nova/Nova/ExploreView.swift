//
//  ExploreView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI

struct ExploreView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject var haptics: HapticsManager
    @EnvironmentObject var achievements: AchievementManager

    @State private var up: [(object: CelestialObject, pos: Horizontal)] = []
    @State private var down: [CelestialObject] = []
    @State private var sweeping = false
    @State private var lastSweep: (id: String, time: Date)?

    var body: some View {
        Screen(title: "Explore") {
            if location.coordinate(demo: persistence.settings.demoMode) == nil {
                Panel { Label("Location needed", systemImage: "location").font(AppFont.style(.headline, .semibold)); Text(location.statusDescription) }
            } else {
                Panel {
                    Text("Above the horizon now").sectionHeader()
                    Text("\(up.count) of the objects I know are above your horizon. The list is sorted from brightest to faintest, and updates every minute.")
                        .font(AppFont.style(.subheadline))
                }

                AppButton(title: "Hear what's up now", systemImage: "speaker.wave.2") { tour() }

                Toggle(isOn: $sweeping) {
                    Text("Sweep mode: announce objects as you point at them").font(AppFont.style(.body, .semibold))
                }
                .padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHint("Move your phone slowly across the sky. A sound and a spoken name tell you when you pass an object.")

                DemoControls()

                ForEach(up, id: \.object.id) { item in
                    NavigationLink { ObjectDetailView(object: item.object) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.object.title)
                            Text("\(item.object.kind.label.capitalized). \(AstronomyEngine.describeLocation(item.pos)).")
                                .font(AppFont.style(.subheadline))
                        }
                    }
                    .buttonStyle(BigButtonStyle(prominent: false))
                    .accessibilityElement(children: .combine)
                }

                if !down.isEmpty {
                    Panel {
                        Text("Below the horizon right now").sectionHeader()
                        Text(down.map(\.title).joined(separator: ", "))
                    }
                }
            }

            Text("Learn without pointing").sectionHeader().padding(.top, 8)
            Text("Constellations and deep-sky objects are for listening and learning. This app cannot locate them with your phone.")
                .font(AppFont.style(.subheadline))
            ForEach(Catalog.all.filter { !$0.isLocatable }) { o in
                NavigationLink { ObjectDetailView(object: o) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(o.title)
                        Text("\(o.kind.label.capitalized), learning only.").font(AppFont.style(.subheadline))
                    }
                }
                .buttonStyle(BigButtonStyle(prominent: false))
                .accessibilityElement(children: .combine)
            }
            SpeechControls()
        }
        .task {
            location.start()
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        .onChange(of: sweeping) { _, on in
            if on {
                motion.start()
                speech.speak("Sweep mode on. Hold your phone with its back toward the sky and move it slowly. I'll say the name of any object you pass. Stand still on safe ground.")
            } else {
                motion.stop()
                speech.speak("Sweep mode off.")
            }
        }
        .onChange(of: motion.pointing) { _, p in if sweeping, let p { sweep(p) } }
        .onDisappear { sweeping = false; motion.stop(); speech.stop() }
    }

    private func refresh() {
        guard let c = location.coordinate(demo: persistence.settings.demoMode) else { up = []; down = []; return }
        let now = Date()
        var u: [(CelestialObject, Horizontal)] = [], d: [CelestialObject] = []
        for o in Catalog.locatable {
            guard let p = AstronomyEngine.position(of: o, date: now, latitude: c.latitude, longitude: c.longitude) else { continue }
            if p.altitude > 0 { u.append((o, p)) } else { d.append(o) }
        }
        u.sort { ($0.0.magnitude ?? 9) < ($1.0.magnitude ?? 9) }
        up = u.map { (object: $0.0, pos: $0.1) }
        down = d
    }

    private func tour() {
        guard !up.isEmpty else {
            speech.narrate("None of the objects I know are above the horizon right now."); return
        }
        let parts = up.prefix(6).map { "\($0.object.spokenName), \(AstronomyEngine.describeLocation($0.pos))" }
        speech.narrate("\(up.count) objects are above the horizon. Starting with the brightest: " + parts.joined(separator: ". ") + ".")
    }

    private func sweep(_ p: Horizontal) {
        guard motion.isUsableForIdentify, let c = location.coordinate(demo: persistence.settings.demoMode) else { return }
        let now = Date()
        let r = ObjectMatcher.match(pointing: p, uncertainty: motion.uncertainty, date: now, latitude: c.latitude, longitude: c.longitude)
        guard case .confident(let o, _) = r else { return }
        if let last = lastSweep, last.id == o.id, now.timeIntervalSince(last.time) < 12 { return }
        lastSweep = (o.id, now)
        audio.play(SoundEffect.forDiscovery(o.kind))
        haptics.play(.select)
        speech.speak("\(o.spokenName), \(o.kind == .star ? "a star in \(o.constellation)" : "a \(o.kind.label)").")
        achievements.celebrateDiscovery(o, method: .identified)
    }
}
