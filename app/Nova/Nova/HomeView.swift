//
//  HomeView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var haptics: HapticsManager
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var router: AppRouter

    static let introText = "Welcome to Nova. Point your phone at the sky and I'll tell you what's there, or guide you to a star with vibrations and sound. " +
        "I work out where objects should be from your location, the time, and your phone's compass. I can't see the sky, so I can't tell if clouds or buildings are in the way. " +
        "For your safety, stand still on safe ground while you point, and never walk while using the app. You can skip this introduction in Settings."

    private var greeting: String { auth.firstName.map { "Hi, \($0)!" } ?? "Hi there!" }

    private var moonLine: String {
        let p = AstronomyEngine.moonPhase(date: Date())
        return "\(p.name.capitalized), about \(Int((p.fraction * 100).rounded())) percent lit"
    }

    var body: some View {
        Screen(title: "Nova", showsTitle: false) {
            NovaHeader()
                .padding(.top, 4)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(AppFont.serif(size: 46))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("The universe is for everyone.")
                    .font(AppFont.style(.title3))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.bottom, 4)

            if persistence.settings.demoMode {
                Panel {
                    Label("Demo mode is on", systemImage: "wand.and.stars").font(AppFont.style(.headline, .semibold))
                    Text("Pointing is simulated and the location is a fixed demo location. Turn it off in Settings to use the real sensors.")
                        .font(AppFont.style(.subheadline))
                }
                .accessibilityElement(children: .combine)
            }

            if !SetupCheck.missingPermissions.isEmpty {
                Panel {
                    Label("Setup needed", systemImage: "exclamationmark.triangle").font(AppFont.style(.headline, .semibold))
                    Text("These permission texts are missing from the app, so iOS never shows its popups: " +
                         SetupCheck.missingPermissions.map(\.title).joined(separator: ", ") +
                         ". Open Settings > Setup check for the fix.")
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

            // Tonight, as a glass card.
            HStack(spacing: 14) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.violet)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tonight").font(AppFont.style(.subheadline, .semibold)).foregroundStyle(Theme.textSecondary)
                    Text(moonLine).font(AppFont.style(.headline, .semibold)).foregroundStyle(Theme.text)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .novaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tonight. Moon phase: \(moonLine).")

            if auth.isAvailable && !auth.isSignedIn {
                AppButton(title: "Sign in with Google", systemImage: "person.crop.circle", prominent: false,
                          hint: "Optional. Greets you by name. Everything works without it.") {
                    Task { await auth.signInWithGoogle(); if let m = auth.message { speech.announce(m) } }
                }
            }

            AppButton(title: "Find an object", systemImage: "scope",
                      hint: "Choose a star, planet or the Moon and be guided to it with vibration and sound.") {
                router.tab = .find
            }

            Button {
                haptics.play(.select)
                router.tab = .explore
            } label: {
                FeatureRow(icon: "binoculars.fill", title: "Explore", subtitle: "Hear what is above the horizon tonight")
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("Explore")
            .accessibilityHint("Hear what is above the horizon tonight.")

            Button {
                haptics.play(.select)
                router.tab = .identify
            } label: {
                FeatureRow(icon: "questionmark.circle.fill", title: "What am I pointing at?", subtitle: "Point at the sky and hear what should be there")
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityLabel("What am I pointing at?")
            .accessibilityHint("Point your phone at the sky and hear which object should be there.")

            NavigationLink { SkyCameraView() } label: {
                FeatureRow(icon: "camera.viewfinder", title: "Sky Camera", subtitle: "Live camera with labels, for sighted helpers", tint: Theme.violet)
            }
            .buttonStyle(CardButtonStyle())
            .accessibilityHint("A live camera view with labels, for sighted helpers. It can also describe the view aloud.")

            AppButton(title: "Hear the introduction", systemImage: "speaker.wave.2", prominent: false) {
                speech.narrate(Self.introText)
            }
            SpeechControls()
        }
        .onAppear {
            if !persistence.settings.hasHeardIntro {
                persistence.settings.hasHeardIntro = true
                speech.narrate("\(greeting) " + Self.introText)
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
