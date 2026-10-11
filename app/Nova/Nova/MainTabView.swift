//
//  MainTabView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit
import Combine

enum AppTab: Hashable { case home, explore, find, identify, more }

/// Lets any screen jump to a tab (the home screen's big buttons use it).
@MainActor
final class AppRouter: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var tab: AppTab = .home { willSet { objectWillChange.send() } }
}

/// The bottom tab bar. It is the system TabView, so on iOS 26 and later it is Apple's Liquid Glass bar, floating over the
/// sky, and it works with VoiceOver, Dynamic Type and Voice Control with no extra effort. On earlier iPhones it falls
/// back to a frosted dark bar.
struct MainTabView: View {
    @StateObject private var router = AppRouter()
    @EnvironmentObject var haptics: HapticsManager

    init() {
        // Before iOS 26 give the bar a dark frosted look. On iOS 26+ leave the system's glass untouched.
        if #unavailable(iOS 26.0) {
            let a = UITabBarAppearance()
            a.configureWithDefaultBackground()
            a.backgroundEffect = UIBlurEffect(style: .systemThinMaterialDark)
            a.backgroundColor = UIColor(red: 0.031, green: 0.055, blue: 0.106, alpha: 0.55)
            let normal = UIColor(red: 0.659, green: 0.714, blue: 0.792, alpha: 1)
            let selected = UIColor(red: 0.408, green: 0.882, blue: 1.0, alpha: 1)
            for item in [a.stackedLayoutAppearance, a.inlineLayoutAppearance, a.compactInlineLayoutAppearance] {
                item.normal.iconColor = normal; item.normal.titleTextAttributes = [.foregroundColor: normal]
                item.selected.iconColor = selected; item.selected.titleTextAttributes = [.foregroundColor: selected]
            }
            UITabBar.appearance().standardAppearance = a
            UITabBar.appearance().scrollEdgeAppearance = a
        }
    }

    var body: some View {
        TabView(selection: Binding(get: { router.tab }, set: { router.tab = $0 })) {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            NavigationStack { ExploreView() }
                .tabItem { Label("Explore", systemImage: "binoculars.fill") }
                .tag(AppTab.explore)

            NavigationStack { FindObjectView() }
                .tabItem { Label("Find", systemImage: "scope") }
                .tag(AppTab.find)

            NavigationStack { IdentifyView() }
                .tabItem { Label("Identify", systemImage: "questionmark.circle.fill") }
                .tag(AppTab.identify)

            NavigationStack { MoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(AppTab.more)
        }
        .tint(Theme.accent)
        .environmentObject(router)
        .onChange(of: router.tab) { _, _ in haptics.play(.select) }
    }
}

/// Everything that isn't one of the four main tools.
struct MoreView: View {
    @EnvironmentObject var speech: SpeechManager

    var body: some View {
        Screen(title: "More") {
            NavigationLink { SkyCameraView() } label: {
                FeatureRow(icon: "camera.viewfinder", title: "Sky Camera",
                           subtitle: "Live camera with labels, for sighted helpers")
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink { DiscoveriesView() } label: {
                FeatureRow(icon: "book.fill", title: "My Discoveries", subtitle: "Everything you have found so far", tint: Theme.violet)
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink { MissionsView() } label: {
                FeatureRow(icon: "flag.fill", title: "Missions", subtitle: "Small goals for tonight", tint: Theme.violet)
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink { AchievementsView() } label: {
                FeatureRow(icon: "rosette", title: "Achievements", subtitle: "Badges you have earned", tint: Theme.violet)
            }
            .buttonStyle(CardButtonStyle())

            NavigationLink { SettingsView() } label: {
                FeatureRow(icon: "gearshape.fill", title: "Settings", subtitle: "Voice, vibration, sound and account", tint: Theme.textSecondary)
            }
            .buttonStyle(CardButtonStyle())

            AppButton(title: "Hear the introduction", systemImage: "speaker.wave.2", prominent: false) {
                speech.narrate(HomeView.introText)
            }
            SpeechControls()
        }
    }
}
