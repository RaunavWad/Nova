import SwiftUI

struct IdentifyView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var achievements: AchievementManager
    @EnvironmentObject var haptics: HapticsManager
    @EnvironmentObject var audio: AudioManager

    enum Outcome {
        case none
        case confident(CelestialObject, String)
        case ambiguous([CelestialObject], String)
        case nothing(CelestialObject, String)
        case message(String)
    }

    @State private var outcome: Outcome = .none
    @State private var heardCaveat = false

    var body: some View {
        Screen(title: "What am I pointing at?") {
            Panel {
                Text("How it works").sectionHeader()
                Text("Hold your phone with its back toward the sky, keep it steady, then press the button. I work out which objects should be in that direction from your location, the time and your compass. I can't see the sky, so I can't tell about clouds or obstructions.")
                    .font(AppFont.style(.subheadline))
                Text("Compass: \(motion.quality.spoken)").font(AppFont.style(.subheadline))
            }

            AppButton(title: "What am I pointing at?", systemImage: "scope",
                      hint: "Reads your phone's direction and tells you which object should be there") { identify() }

            switch outcome {
            case .none: EmptyView()
            case .message(let t):
                Panel { Label("Can't tell yet", systemImage: "exclamationmark.triangle").font(AppFont.style(.headline, .semibold)); Text(t) }
            case .confident(let o, let t):
                Panel { Label(o.title, systemImage: "checkmark.seal").font(AppFont.style(.headline, .semibold)); Text(t) }
                    .accessibilityElement(children: .combine)
                objectActions(o)
            case .ambiguous(let list, let t):
                Panel { Label("More than one possibility", systemImage: "list.bullet").font(AppFont.style(.headline, .semibold)); Text(t) }
                    .accessibilityElement(children: .combine)
                ForEach(list) { o in
                    NavigationLink { ObjectDetailView(object: o) } label: { Text("Hear about \(o.name)") }
                        .buttonStyle(BigButtonStyle(prominent: false))
                }
            case .nothing(let nearest, let t):
                Panel { Label("Nothing bright here", systemImage: "circle.dashed").font(AppFont.style(.headline, .semibold)); Text(t) }
                    .accessibilityElement(children: .combine)
                NavigationLink { FindObjectView(initialTarget: nearest) } label: { Label("Guide me to \(nearest.name)", systemImage: "scope") }
                    .buttonStyle(BigButtonStyle(prominent: false))
            }

            DemoControls()
            SpeechControls()
        }
        .onAppear { location.start(); motion.start() }
        .onDisappear { motion.stop(); speech.stop() }
    }

    @ViewBuilder private func objectActions(_ o: CelestialObject) -> some View {
        AppButton(title: "Learn more", systemImage: "text.book.closed", prominent: false) {
            speech.narrate(speech.deeperDescription(of: o)); achievements.noteLearned(o, story: false)
        }
        if let story = o.story {
            AppButton(title: "Hear the story", systemImage: "books.vertical", prominent: false) {
                speech.narrate(story); achievements.noteLearned(o, story: true)
            }
        }
        NavigationLink { ObjectDetailView(object: o) } label: { Label("Open details", systemImage: "info.circle") }
            .buttonStyle(BigButtonStyle(prominent: false))
    }

    // MARK: Identify

    private func fail(_ text: String) {
        outcome = .message(text)
        haptics.play(.warning)
        audio.play(.warning)
        speech.narrate(text)
    }

    private func identify() {
        let demo = persistence.settings.demoMode
        guard let c = location.coordinate(demo: demo) else {
            fail(location.isDenied ? "I need your location to know which stars are overhead. Please allow location access in the Settings app, or try Demo mode."
                                   : "I'm still waiting for your location. Try again in a moment.")
            return
        }
        guard motion.isUsableForIdentify, let p = motion.pointing else {
            fail("I don't have a reliable compass reading. \(motion.quality.spoken) Move your phone slowly in a figure eight, then try again.")
            return
        }
        let now = Date()
        let u = motion.uncertainty
        let result = ObjectMatcher.match(pointing: p, uncertainty: u, date: now, latitude: c.latitude, longitude: c.longitude)
        let sunAlt = AstronomyEngine.sunHorizontal(date: now, latitude: c.latitude, longitude: c.longitude).altitude

        var tail = ""
        if sunAlt > -6 { tail += " It's still fairly bright out, so you may not be able to see it." }
        if motion.quality < .high { tail += " My compass is only \(motion.quality == .medium ? "fairly" : "roughly") accurate right now, so treat this as approximate." }
        if !heardCaveat {
            heardCaveat = true
            tail += " I calculate this from your phone's direction. I can't see the sky, so I can't tell about clouds or buildings."
        }
        if demo { tail = " Demo mode: simulated pointing." + tail }

        switch result {
        case .confident(let o, _):
            let place = o.kind == .star ? "It's part of the constellation \(o.constellation) and is \(o.distance) away." : "It is \(o.distance)."
            let ask = o.story != nil ? "Would you like to learn its story?" : "Would you like to learn more?"
            let text = "You're pointing toward \(o.spokenName). \(o.short) \(place) \(ask)\(tail)"
            outcome = .confident(o, text)
            speech.narrate(text)
            achievements.celebrateDiscovery(o, method: .identified)
        case .ambiguous(let list):
            let objs = list.map { $0.object }
            let names = objs.map(\.spokenName).joined(separator: ", or ")
            let text = "I can't be sure. These are all close to where you're pointing: \(names). Choose one to hear about, or hold still and try again.\(tail)"
            outcome = .ambiguous(objs, text)
            speech.narrate(text)
        case .nothingNear(let nearest, let sep, let dAz, let dAlt):
            let text = "I don't expect any bright object right where you're pointing. The nearest one is \(nearest.spokenName), about \(Int(sep.rounded())) degrees away: \(ObjectMatcher.relativeDirection(dAzimuth: dAz, dAltitude: dAlt)).\(tail)"
            outcome = .nothing(nearest, text)
            speech.narrate(text)
        case .belowHorizon:
            let text = "You're pointing below the horizon, so there is nothing to see there. Raise your phone toward the sky."
            outcome = .message(text)
            speech.narrate(text)
        case .unreliable(let why):
            fail(why)
        }
    }
}
