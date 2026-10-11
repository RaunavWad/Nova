//
//  AppFont.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit
import CoreText

enum AppFont {
    enum Face { case sans, serif }

    private(set) static var available: Set<String> = []
    private static var didRegister = false

    /// Call once, as early as possible (first line of the App's init).
    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        var found: Set<String> = []
        if let walker = FileManager.default.enumerator(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil) {
            for case let url as URL in walker {
                let ext = url.pathExtension.lowercased()
                guard ext == "ttf" || ext == "otf" else { continue }
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)   // "already registered" is fine
                if let provider = CGDataProvider(url: url as CFURL), let cg = CGFont(provider),
                   let ps = cg.postScriptName as String? { found.insert(ps) }
            }
        }
        available = found
    }

    private static func first(of names: [String]) -> String? { names.first { available.contains($0) } }

    static var serifName: String? { first(of: ["InstrumentSerif-Regular"]) }

    static func sansName(_ weight: Font.Weight) -> String? {
        switch weight {
        case .bold, .heavy, .black: return first(of: ["InstrumentSans-Bold", "InstrumentSans-SemiBold"])
        case .semibold: return first(of: ["InstrumentSans-SemiBold", "InstrumentSans-Bold"])
        case .medium: return first(of: ["InstrumentSans-Medium", "InstrumentSans-Regular"])
        default: return first(of: ["InstrumentSans-Regular"])
        }
    }

    static var status: String {
        let sans = sansName(.regular) != nil ? "Instrument Sans: loaded." : "Instrument Sans: not found, using the system font."
        let serif = serifName != nil ? "Instrument Serif: loaded." : "Instrument Serif: not found, using the system serif."
        return sans + " " + serif + (available.isEmpty ? " No font files were found in the app. Check that they are added to the Nova target." : "")
    }

    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 36
        case .title: return 30
        case .title2: return 24
        case .title3: return 21
        case .headline: return 18
        case .body: return 18
        case .callout: return 17
        case .subheadline: return 16
        case .footnote: return 14
        case .caption: return 13
        case .caption2: return 12
        @unknown default: return 18
        }
    }

    /// Main entry point: `.font(AppFont.style(.headline, .semibold))`.
    static func style(_ style: Font.TextStyle, _ weight: Font.Weight = .regular, face: Face = .sans) -> Font {
        let pt = size(style)
        switch face {
        case .serif:
            if let n = serifName { return .custom(n, size: pt, relativeTo: style) }
            return .system(style, design: .serif).weight(weight)
        case .sans:
            if let n = sansName(weight) { return .custom(n, size: pt, relativeTo: style) }
            if let n = sansName(.regular) { return .custom(n, size: pt, relativeTo: style).weight(weight) }
            return .system(style).weight(weight)
        }
    }

    static func display(_ style: Font.TextStyle = .largeTitle) -> Font { self.style(style, face: .serif) }

    static func serif(size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        if let n = serifName { return .custom(n, size: size, relativeTo: style) }
        return .system(size: size, design: .serif)
    }


    static func configureAppearance() {
        func scaled(_ name: String?, _ style: UIFont.TextStyle, _ pt: CGFloat) -> UIFont? {
            guard let name, let f = UIFont(name: name, size: pt) else { return nil }
            return UIFontMetrics(forTextStyle: style).scaledFont(for: f)
        }
        let text = UIColor(red: 0.957, green: 0.969, blue: 1.0, alpha: 1)
        let a = UINavigationBarAppearance()
        a.configureWithTransparentBackground()
        var large: [NSAttributedString.Key: Any] = [.foregroundColor: text]
        var inline: [NSAttributedString.Key: Any] = [.foregroundColor: text]
        if let f = scaled(serifName, .largeTitle, 38) { large[.font] = f }
        if let f = scaled(sansName(.semibold), .headline, 18) { inline[.font] = f }
        a.largeTitleTextAttributes = large
        a.titleTextAttributes = inline
        UINavigationBar.appearance().standardAppearance = a
        UINavigationBar.appearance().scrollEdgeAppearance = a
        UINavigationBar.appearance().compactAppearance = a
    }
}
