//
//  SettingsView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject var haptics: HapticsManager
    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var auth: AuthManager
    @State private var confirmReset = false

    var body: some View {
        Form {
            SetupCheckSection()

            Section("Speech") {
                slider("Speech speed", value: $persistence.settings.speechRate, range: 0.1...1, step: 0.05)
                Picker("Amount of speech", selection: $persistence.settings.verbosity) {
                    ForEach(Verbosity.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Use VoiceOver for announcements when it is on", isOn: $persistence.settings.useVoiceOverAnnouncements)
                Toggle("Premium voice (ElevenLabs)", isOn: $persistence.settings.premiumVoice)
                    .disabled(!speech.premiumAvailable)
                Text(speech.premiumAvailable
                     ? "When on, the text of descriptions you ask to hear is sent to ElevenLabs to be turned into speech, and saved on this iPhone so it works offline next time. Your location, camera and sensor data are never sent. If it is slow or offline, the built-in voice is used."
                     : "Premium voice isn't set up, so the built-in voice is used. " + (ElevenLabsClient.configurationProblem ?? ""))
                    .font(AppFont.style(.footnote))
                if speech.premiumAvailable {
                    Button("Test premium voice") { Task { await speech.checkPremium() } }.hapticTap()
                }
                if let status = speech.premiumStatus {
                    Text(status).font(AppFont.style(.footnote)).foregroundStyle(Theme.violet)
                }
                slider("Narration volume", value: $persistence.settings.narrationVolume, range: 0.2...1, step: 0.05)
                Button("Test the voice") { speech.narrate("This is how Nova sounds at the current speed and volume.") }.hapticTap()
                Button("Hear the introduction again") { speech.narrate(HomeView.introText) }.hapticTap()
            }

            Section {
                Picker("Guidance style", selection: $persistence.settings.guidanceStyle) {
                    ForEach(GuidanceStyle.allCases) { Text($0.label).tag($0) }
                }
                slider("Seconds between spoken hints", value: $persistence.settings.guidanceSpeechInterval, range: 3...20, step: 1, unit: "seconds", percent: false)
                Toggle("Vibration", isOn: $persistence.settings.hapticsEnabled)
                slider("Vibration strength", value: $persistence.settings.hapticIntensity, range: 0.2...1, step: 0.1)
                    .disabled(!haptics.isCoreHapticsSupported)
                Picker("Pointing direction", selection: $persistence.settings.pointingMode) {
                    ForEach(PointingMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Guidance tone", isOn: $persistence.settings.guidanceTone)
                Toggle("3D sound (best with headphones)", isOn: $persistence.settings.spatialAudio)
                NavigationLink("Calibrate the compass") { CalibrationView() }.hapticTap()
                NavigationLink("Learn the vibration language") { HapticLanguageView() }.hapticTap()
            } header: { Text("Guidance") } footer: {
                Text(haptics.isCoreHapticsSupported
                     ? "Vibration strength is adjustable on this iPhone."
                     : "This device can't change vibration strength; the system chooses it.")
            }

            Section("Sound") {
                Toggle("Ambient space music", isOn: $persistence.settings.ambienceEnabled)
                slider("Music volume", value: $persistence.settings.ambienceVolume, range: 0...1, step: 0.05)
                Toggle("Sound effects", isOn: $persistence.settings.effectsEnabled)
                slider("Effects volume", value: $persistence.settings.effectsVolume, range: 0...1, step: 0.05)
                Button("Play a sample effect") { audio.play(.star) }.hapticTap()
                Button(audio.isPaused ? "Resume all audio" : "Pause all audio") { audio.isPaused ? audio.resume() : audio.pause() }.hapticTap()
            }

            Section {
                Toggle("Demo mode", isOn: $persistence.settings.demoMode)
            } header: { Text("Demo mode") } footer: {
                Text("Demo mode uses simulated pointing and a fixed demo location so you can try the app without the sensors or outdoors, for example in the Simulator. Discoveries made in demo mode are labeled as such.")
            }

            Section {
                if !auth.isAvailable || auth.setupProblem != nil {
                    Text((auth.setupProblem ?? "Sign-in isn't set up in this build.") + " Nova works fully without an account.")
                } else if auth.isSignedIn {
                    Text("Signed in as \(auth.displayName ?? auth.email ?? "your Google account").")
                    Button("Sign out") { auth.signOut(); if let m = auth.message { speech.announce(m) } }.hapticTap()
                } else {
                    Button {
                        Task { await auth.signInWithGoogle(); if let m = auth.message { speech.announce(m) } }
                    } label: { Label("Sign in with Google", systemImage: "person.crop.circle") }
                    .disabled(auth.isBusy)
                }
                if let m = auth.message { Text(m) }
            } header: { Text("Account (optional)") } footer: {
                Text("You never need an account. Signing in only shows who you are here; your discoveries and location are not uploaded.")
            }

            Section {
                Text("Your location is used only on this iPhone to calculate where objects are. Camera pictures are shown live and are never saved or analysed. Progress is saved only on this device. If you choose to sign in, Google and Firebase receive only your sign-in details.")
                Text(location.statusDescription)
                Button("Reset my progress", role: .destructive) { confirmReset = true }.hapticTap()
            } header: { Text("Privacy") }

            Section("Fonts") {
                Text(AppFont.status)
            }

            Section("About accuracy") {
                Text("Nova calculates where objects should be. It doesn't see the sky, so it can't tell about clouds or buildings. The phone's compass is typically accurate to a few degrees at best, so finding an object means getting close, not telescope-level aiming.")
            }
        }
        .font(AppFont.style(.body))
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(StarfieldBackground())
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .onChange(of: persistence.settings) { _, _ in haptics.play(.select) }
        .onChange(of: persistence.settings.demoMode) { _, _ in if motion.isRunning { motion.start() } }
        .confirmationDialog("Reset all discoveries and achievements?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset progress", role: .destructive) { persistence.resetProgress(); speech.speak("Progress reset.") }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func slider<V: BinaryFloatingPoint>(_ title: String, value: Binding<V>, range: ClosedRange<Double>, step: Double,
                                                unit: String = "percent", percent: Bool = true) -> some View where V.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading) {
            Text(title)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = V($0) }), in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue(percent ? "\(Int(Double(value.wrappedValue) * 100)) percent" : "\(Int(Double(value.wrappedValue))) \(unit)")
        }
    }
}

// MARK: - Haptic language (documented and playable)

struct HapticLanguageView: View {
    @EnvironmentObject var haptics: HapticsManager
    @EnvironmentObject var speech: SpeechManager

    var body: some View {
        Screen(title: "Vibration Language") {
            Text("Tap any pattern to feel it. Each one is also described in words, and the app always speaks or shows important messages too.")
                .font(AppFont.style(.subheadline))
            ForEach(HapticPattern.allCases, id: \.self) { p in
                Button {
                    haptics.play(p)
                    speech.speak(p.meaning, remember: false)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized)
                        Text(p.meaning).font(AppFont.style(.subheadline))
                    }
                }
                .buttonStyle(BigButtonStyle(prominent: false))
                .accessibilityElement(children: .combine)
                .accessibilityHint("Plays this vibration")
            }
            if !haptics.isCoreHapticsSupported {
                Text("This device uses basic system vibrations, so patterns may feel simpler.").font(AppFont.style(.footnote))
            }
            SpeechControls()
        }
    }
}
