//
//  SetUpCheck.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit

/// A developer aid: looks inside the running app and reports which setup pieces are really there. When a permission
/// popup never appears, the cause is nearly always a missing Info entry, and this shows it at a glance.
enum SetupCheck {
    struct Item: Identifiable {
        let id: String
        let ok: Bool
        let title: String
        let fix: String
        /// Missing pieces that stop iOS permission popups from ever appearing.
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
            Item(id: "google-plist", ok: Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil,
                 title: "GoogleService-Info.plist",
                 fix: "Drag the downloaded file into the Nova folder in Xcode with the Nova target ticked."),
            Item(id: "google-scheme", ok: schemes.contains { $0.hasPrefix("com.googleusercontent.apps") },
                 title: "Google sign-in URL scheme",
                 fix: "Nova target > Info > URL Types > + > paste REVERSED_CLIENT_ID from the plist into URL Schemes."),
            Item(id: "eleven", ok: ElevenLabsClient.configurationProblem == nil,
                 title: "ElevenLabs Secrets.plist",
                 fix: ElevenLabsClient.configurationProblem ?? ""),
            Item(id: "fonts", ok: AppFont.sansName(.regular) != nil && AppFont.serifName != nil,
                 title: "Instrument Sans and Serif fonts",
                 fix: "Drag the .ttf files into the Nova folder in Xcode with the Nova target ticked."),
            Item(id: "logo", ok: UIImage(named: "NovaLogo") != nil,
                 title: "NovaLogo image",
                 fix: "Assets.xcassets > New Image Set named exactly NovaLogo, then drag the 1024 x 1024 logo in.")
        ]
    }

    static var missingPermissions: [Item] { items.filter { $0.isPermission && !$0.ok } }
}

/// Shown in Settings: every piece with a tick or a cross, and the fix for each cross.
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
