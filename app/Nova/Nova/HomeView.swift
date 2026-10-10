import SwiftUI

struct HomeView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var haptics: HapticsManager
    @EnvironmentObject var auth: AuthManager

    static let introText = "Welcome to Nova. Point your phone at the sky and I'll tell you what's there, or guide you to a star with vibrations and sound. " +
        "I work out where objects should be from your location, the time, and your phone's compass. I can't see the sky, so I can't tell if clouds or buildings are in the way. " +
        "For your safety, stand still on safe ground while you point, and never walk while using the app. You can skip this introduction in Settings."

    private var greeting: String { auth.firstName.map { "Hi, \($0)" } ?? "Hi there" }

    var body: some View {
        Screen(title: "Nova") {
            if persistence.settings.demoMode {
                Panel {
                    Label("Demo mode is on", systemImage: "wand.and.stars").font(AppFont.style(.headline, .semibold))
                    Text("Pointing is simulated and the location is a fixed demo location. Turn it off in Settings to use the real sensors.")
                        .font(AppFont.style(.subheadline))
                }
                .accessibilityElement(children: .combine)
            }

            if location.isDenied && !persistence.settings.demoMode {
                Panel {
                    Label("Location is off", systemImage: "location.slash").font(AppFont.style(.headline, .semibold))
                    Text(location.statusDescription).font(AppFont.style(.subheadline))
                    AppButton(title: "Open iPhone Settings", systemImage: "gearshape", prominent: false) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }

            Text(greeting)
                .font(AppFont.display(.largeTitle)).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("Explore the night sky with sound and touch.").font(AppFont.display(.title3)).foregroundStyle(Theme.textSecondary)

            if auth.isAvailable && !auth.isSignedIn {
                AppButton(title: "Sign in with Google", systemImage: "person.crop.circle", prominent: false,
                          hint: "Optional. Greets you by name. Everything works without it.") {
                    Task { await auth.signInWithGoogle(); if let m = auth.message { speech.announce(m) } }
                }
            }

            NavigationLink { ExploreView() } label: { Label("Explore", systemImage: "binoculars") }
                .buttonStyle(BigButtonStyle()).accessibilityHint("Hear what is above the horizon tonight.")
            NavigationLink { FindObjectView() } label: { Label("Find an Object", systemImage: "scope") }
                .buttonStyle(BigButtonStyle()).accessibilityHint("Choose a star, planet or the Moon and be guided to it with vibration and sound.")
            NavigationLink { IdentifyView() } label: { Label("What am I pointing at?", systemImage: "questionmark.circle") }
                .buttonStyle(BigButtonStyle()).accessibilityHint("Point your phone at the sky and hear which object should be there.")
            NavigationLink { SkyCameraView() } label: { Label("Sky Camera", systemImage: "camera.viewfinder") }
                .buttonStyle(BigButtonStyle(prominent: false))
                .accessibilityHint("A live camera view with labels, for sighted helpers. It can also describe the view aloud.")
            NavigationLink { DiscoveriesView() } label: { Label("My Discoveries", systemImage: "book") }
                .buttonStyle(BigButtonStyle(prominent: false))
            NavigationLink { MissionsView() } label: { Label("Missions", systemImage: "flag") }
                .buttonStyle(BigButtonStyle(prominent: false))
            NavigationLink { AchievementsView() } label: { Label("Achievements", systemImage: "rosette") }
                .buttonStyle(BigButtonStyle(prominent: false))
            NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                .buttonStyle(BigButtonStyle(prominent: false))

            AppButton(title: "Hear the introduction", systemImage: "speaker.wave.2", prominent: false) {
                speech.narrate(Self.introText)
            }
            SpeechControls()
        }
        .onAppear {
            if !persistence.settings.hasHeardIntro {
                persistence.settings.hasHeardIntro = true
                speech.narrate("\(greeting). " + Self.introText)
            }
        }
    }
}

/// Shows and narrates everything we know about one object. Reading it counts toward "learned" progress.
struct ObjectDetailView: View {
    let object: CelestialObject
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var achievements: AchievementManager
    @EnvironmentObject var persistence: PersistenceManager

    var body: some View {
        Screen(title: object.name.capitalized) {
            Panel {
                Text("\(object.kind.label.capitalized) in \(object.constellation)").font(AppFont.style(.headline, .semibold))
                Text(object.short)
                Text("Distance: \(object.distance).")
                if let m = object.magnitude { Text("Brightness: magnitude \(String(format: "%.1f", m)). Smaller or more negative numbers are brighter.") }
                if !object.isLocatable {
                    Text("This is a learning topic. It can't be located with phone sensors, so there is no pointing guidance for it.")
                        .font(AppFont.style(.subheadline)).foregroundStyle(Theme.violet)
                }
            }.accessibilityElement(children: .combine)

            AppButton(title: "Hear a short description", systemImage: "speaker.wave.2") {
                speech.narrate(speech.shortDescription(of: object))   // only the deeper description counts as "learned"
            }
            AppButton(title: "Learn more", systemImage: "text.book.closed", prominent: false) {
                speech.narrate(speech.deeperDescription(of: object))
                achievements.noteLearned(object, story: false)
            }
            if let story = object.story {
                AppButton(title: "Hear the story", systemImage: "books.vertical", prominent: false) {
                    speech.narrate(story)
                    achievements.noteLearned(object, story: true)
                }
            }
            AppButton(title: "Did you know?", systemImage: "lightbulb", prominent: false) {
                speech.narrate(object.didYouKnow)
            }
            SpeechControls()

            if object.isLocatable {
                NavigationLink { FindObjectView(initialTarget: object) } label: { Label("Find this object", systemImage: "scope") }
                    .buttonStyle(BigButtonStyle())
            }

            if object.deeper.count > 0 {
                Panel {
                    Text("More").sectionHeader()
                    Text(object.deeper)
                    if let story = object.story { Text(story).foregroundStyle(Theme.textSecondary) }
                    Text("Did you know? \(object.didYouKnow)")
                }
            }
        }
    }
}
