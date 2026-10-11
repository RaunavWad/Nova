//
//  SetUpCheck.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit


enum SetupCheck {
    struct Item: Identifiable {
        let id: String
        let ok: Bool
        let title: String
        let fix: String
        var isPermission = false
    }

    static var items: [Item] {
        let info = Bundle.main.infoDictionary ?? [:]
        let schemes = (info["CFBundleURLTypes"] as? [[String: Any]] ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return [
            Item(id: "location", ok: info["NSLocationWhenInUseUsageDescription"] != nil,
                 title: "Location permission text",
                 fix: "Nova target > Build Settings > search \"location when in use\" > set Privacy - Location When In Use Usage Description. Without it the location popup never appears.",
                 isPermission: true),
            Item(id: "camera", ok: info["NSCameraUsageDescription"] != nil,
                 title: "Camera permission text",
                 fix: "Nova target > Build Settings > search \"camera usage\" > set Privacy - Camera Usage Description. Without it the camera popup never appears.",
                 isPermission: true),
            Item(id: "mic", ok: info["NSMicrophoneUsageDescription"] != nil,
                 title: "Microphone permission text (for Ask)",
                 fix: "Nova target > Build Settings > search \"microphone usage\" > set Privacy - Microphone Usage Description, for example: Nova listens to your spoken questions about space.",
                 isPermission: true),
            Item(id: "claude", ok: ClaudeClient.configurationProblem == nil,
                 title: "Anthropic key for Ask",
                 fix: ClaudeClient.configurationProblem ?? ""),
            Item(id: "google-plist", ok: Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil,
                 title: "GoogleService-Info.plist",
                 fix: "Drag the downloaded file into the Nova folder in Xcode with the Nova target ticked."),
            Item(id: "google-scheme", ok: schemes.contains { $0.hasPrefix("com.googleusercontent.apps") },
                 title: "Google sign-in URL scheme",
                 fix: "Nova target > Info > URL Types > + > paste REVERSED_CLIENT_ID from the plist into URL Schemes."),
            Item(id: "eleven", ok: ElevenLabsClient.configurationProblem == nil,
                 title: "ElevenLabs Secrets.plist",
                 fix: ElevenLabsClient.configurationProblem ?? ""),
            Item(id: "sfx", ok: sfxCount == sfxNames.count,
                 title: "ElevenLabs sound effects (\(sfxCount) of \(sfxNames.count))",
                 fix: "Optional. Run scripts/generate_sfx.sh on your Mac, then drag the sfx_ mp3 files from Resources/Sounds into the Nova folder with the Nova target ticked. Without them the app uses built-in synthesized sounds."),
            Item(id: "fonts", ok: AppFont.sansName(.regular) != nil && AppFont.serifName != nil,
                 title: "Instrument Sans and Serif fonts",
                 fix: "Drag the .ttf files into the Nova folder in Xcode with the Nova target ticked."),
            Item(id: "stars", ok: StarCatalog.isLoaded,
                 title: "Star catalog (stars.json)" + (StarCatalog.isLoaded ? ", \(StarCatalog.count) stars" : ""),
                 fix: "Optional. Without it Nova knows 16 stars. Run scripts/make_star_catalog.py on the HYG star database and drag the stars.json it makes into the Nova folder with the Nova target ticked."),
            Item(id: "logo", ok: UIImage(named: "NovaLogo") != nil,
                 title: "NovaLogo image",
                 fix: "Assets.xcassets > New Image Set named exactly NovaLogo, then drag the 1024 x 1024 logo in.")
        ]
    }

    private static let sfxNames = ["star", "planet", "moon", "deepSky", "constellation", "aligned", "achievement", "warning", "confirm"]
    private static var sfxCount: Int {
        sfxNames.filter { Bundle.main.url(forResource: "sfx_\($0)", withExtension: "mp3") != nil }.count
    }

    static var missingPermissions: [Item] { items.filter { $0.isPermission && !$0.ok } }
}

struct SetupCheckSection: View {
    var body: some View {
        Section {
            ForEach(SetupCheck.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Label(item.title, systemImage: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(item.ok ? Theme.accent : Theme.violet)
                    if !item.ok {
                        Text(item.fix).font(AppFont.style(.footnote)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title): \(item.ok ? "ready" : "missing")")
            }
        } header: { Text("Setup check") } footer: {
            Text("For the people building Nova: a cross means that piece is not inside the running app yet.")
        }
    }
}
