//
//  NovaHeader.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit

extension AppFont {
    /// Instrument Sans at an exact point size (still scales with Dynamic Type when used with `.custom(..., relativeTo:)`).
    static func sans(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        if let n = sansName(weight) { return .custom(n, size: size, relativeTo: style) }
        return .system(size: size, weight: weight)
    }
}

/// The Nova logo. Looks for an image set called "NovaLogo" in Assets.xcassets (drop the 1024 x 1024 picture in there);
/// until it is added, a small gradient sparkle is shown instead so the app never shows a blank gap.
struct NovaMark: View {
    var size: CGFloat = 44
    private static let hasLogo = UIImage(named: "NovaLogo") != nil

    var body: some View {
        Group {
            if Self.hasLogo {
                Image("NovaLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.72, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Logo plus the lowercase "nova" wordmark: Instrument Sans bold, 35 pt, 14 pt gap, -1.5 letter spacing.
struct NovaHeader: View {
    var logoSize: CGFloat = 44
    var fontSize: CGFloat = 35
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 14) {
            NovaMark(size: logoSize * min(scale, 1.4))
            Text("nova")
                .font(AppFont.sans(size: fontSize, weight: .bold, relativeTo: .largeTitle))
                .tracking(-1.5)
                .lineLimit(1)
                .foregroundStyle(Theme.text)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nova")
        .accessibilityAddTraits(.isHeader)
    }
}
