//
//  NovaApp.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if canImport(FirebaseCore)
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        #endif
        return true
    }
}

@main
struct NovaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var persistence: PersistenceManager
    @StateObject private var location: LocationManager
    @StateObject private var motion: MotionManager
    @StateObject private var audio: AudioManager
    @StateObject private var speech: SpeechManager
    @StateObject private var haptics: HapticsManager
    @StateObject private var achievements: AchievementManager
    @StateObject private var guidance: GuidanceEngine
    @StateObject private var auth: AuthManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.registerBundledFonts()      // must run before any text is drawn
        AppFont.configureAppearance()
        let p = PersistenceManager()
        let l = LocationManager()
        let m = MotionManager()
        let a = AudioManager()
        let s = SpeechManager()
        let h = HapticsManager()
        let au = AuthManager()
        au.configure()                      // no-op unless Firebase is installed and GoogleService-Info.plist is present

        m.settingsProvider = { p.settings }
        m.declinationProvider = { l.declination }
        m.locationAuthorized = { l.isAuthorized }
        m.saveAzimuthOffset = { p.settings.azimuthOffset = $0 }
        a.settingsProvider = { p.settings }
        s.settingsProvider = { p.settings }
        s.audio = a
        h.settingsProvider = { p.settings }

        _persistence = StateObject(wrappedValue: p)
        _location = StateObject(wrappedValue: l)
        _motion = StateObject(wrappedValue: m)
        _audio = StateObject(wrappedValue: a)
        _speech = StateObject(wrappedValue: s)
        _haptics = StateObject(wrappedValue: h)
        let ach = AchievementManager(persistence: p, speech: s, audio: a, haptics: h)
        _auth = StateObject(wrappedValue: au)
        _achievements = StateObject(wrappedValue: ach)
        _guidance = StateObject(wrappedValue: GuidanceEngine(motion: m, location: l, speech: s, audio: a, haptics: h, persistence: p))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(persistence)
                .environmentObject(location)
                .environmentObject(motion)
                .environmentObject(audio)
                .environmentObject(speech)
                .environmentObject(haptics)
                .environmentObject(achievements)
                .environmentObject(guidance)
                .environmentObject(auth)
                .onOpenURL { auth.handle(url: $0) }
                .preferredColorScheme(.dark)
                .onAppear {
                    audio.start()
                    location.start()
                    persistence.markUsedToday()
                    achievements.evaluate()
                }
                .onChange(of: persistence.settings) { _, new in audio.apply(new) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        guidance.stop(); motion.stop(); speech.stop(); audio.stopAllSounds()
                    } else if phase == .active {
                        audio.start()
                    }
                }
        }
    }
}
