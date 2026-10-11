//
//  ProgressViews.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI


struct DiscoveriesView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var speech: SpeechManager

    private var records: [DiscoveryRecord] {
        persistence.progress.discoveries.sorted { $0.date > $1.date }
    }

    var body: some View {
        Screen(title: "My Discoveries") {
            if records.isEmpty {
                Panel {
                    Text("Nothing yet").sectionHeader()
                    Text("Use Find an Object or What am I pointing at to make your first discovery.")
                }
            } else {
                AppButton(title: "Read my journal aloud", systemImage: "speaker.wave.2") { readAloud() }
                ForEach(records) { r in
                    if let o = Catalog.object(id: r.objectID) {
                        NavigationLink { ObjectDetailView(object: o) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(o.title)
                                Text("\(r.method == .found ? "Found" : "Identified") on \(r.date.formatted(date: .abbreviated, time: .omitted))\(r.demo ? ", in demo mode" : "").")
                                    .font(AppFont.style(.subheadline))
                            }
                        }
                        .buttonStyle(BigButtonStyle(prominent: false))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            SpeechControls()
        }
    }

    private func readAloud() {
        let items = records.compactMap { r -> String? in
            guard let o = Catalog.object(id: r.objectID) else { return nil }
            return "\(o.spokenName), \(r.method == .found ? "found" : "identified") \(r.date.formatted(date: .abbreviated, time: .omitted))\(r.demo ? " in demo mode" : "")"
        }
        speech.narrate("Your journal has \(records.count) discoveries. " + items.joined(separator: ". ") + ".")
    }
}

struct MissionsView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var achievements: AchievementManager

    var body: some View {
        let p = persistence.progress
        let today = Rewards.dailySuggestion()
        Screen(title: "Missions") {
            Panel {
                Text("Optional suggestion for today").sectionHeader()
                Text("Learn about \(today.title). Only if you feel like it: there are no streaks and nothing is lost if you skip a day.")
                Text(achievements.dailyDone ? "Status: done today." : "Status: not done today.").font(AppFont.style(.subheadline))
                NavigationLink { ObjectDetailView(object: today) } label: { Label("Open \(today.title)", systemImage: "arrow.right.circle") }
                    .buttonStyle(BigButtonStyle(prominent: false))
            }

            Text("Missions").sectionHeader()
            Text("Take your time. Missions are about curiosity, not speed, and are always safe to skip.").font(AppFont.style(.subheadline))
            ForEach(Rewards.missions) { m in
                Panel {
                    Text(m.title).font(AppFont.style(.headline, .semibold))
                    Text(m.detail)
                    Text(m.isMet(p) ? "Completed" : "Progress: \(m.progressText(p))")
                        .font(AppFont.style(.subheadline)).foregroundStyle(m.isMet(p) ? Theme.violet : Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            AppButton(title: "Read my progress aloud", systemImage: "speaker.wave.2") {
                let lines = Rewards.missions.map { "\($0.title): \($0.isMet(p) ? "completed" : $0.progressText(p))" }
                speech.narrate(lines.joined(separator: ". ") + ".")
            }
            SpeechControls()
        }
    }
}

struct AchievementsView: View {
    @EnvironmentObject var persistence: PersistenceManager
    @EnvironmentObject var speech: SpeechManager

    var body: some View {
        let p = persistence.progress
        Screen(title: "Achievements") {
            Text("\(p.unlocked.count) of \(Rewards.achievements.count) unlocked").sectionHeader()
            ForEach(Rewards.achievements) { a in
                let date = p.unlocked[a.id]
                Panel {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: date != nil ? a.symbol : "lock")
                            .font(AppFont.style(.title2)).foregroundStyle(date != nil ? Theme.violet : Theme.textSecondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.title).font(AppFont.style(.headline, .semibold))
                            Text(a.detail).font(AppFont.style(.subheadline))
                            Text(date.map { "Unlocked \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Not unlocked yet")
                                .font(AppFont.style(.subheadline)).foregroundStyle(date != nil ? Theme.violet : Theme.textSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            AppButton(title: "Read my achievements aloud", systemImage: "speaker.wave.2") {
                let got = Rewards.achievements.filter { p.unlocked[$0.id] != nil }.map(\.title)
                speech.narrate(got.isEmpty ? "You haven't unlocked any achievements yet. Your first discovery will earn one."
                                           : "You've unlocked \(got.count): " + got.joined(separator: ", ") + ".")
            }
            SpeechControls()
        }
    }
}
