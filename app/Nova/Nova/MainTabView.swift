//
//  MainTabView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit
import Combine

enum AppTab: Hashable { case home, explore, find, ask, more }

@MainActor
final class AppRouter: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var tab: AppTab = .home { willSet { objectWillChange.send() } }
}


struct MainTabView: View {
    @StateObject private var router = AppRouter()
    @EnvironmentObject var haptics: HapticsManager

    init() {
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

            NavigationStack { AskView() }
                .tabItem { Label("Ask", systemImage: "waveform.circle.fill") }
                .tag(AppTab.ask)

            NavigationStack { MoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(AppTab.more)
        }
        .tint(Theme.accent)
        .environmentObject(router)
        .onChange(of: router.tab) { _, _ in haptics.play(.select) }
    }
}

struct MoreView: View {
    @EnvironmentObject var speech: SpeechManager

    var body: some View {
        Screen(title: "More") {
            NavigationLink { IdentifyView() } label: {
                FeatureRow(icon: "questionmark.circle.fill", title: "What am I pointing at?",
                           subtitle: "Point at the sky and hear what should be there")
            }
            .buttonStyle(CardButtonStyle())

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
