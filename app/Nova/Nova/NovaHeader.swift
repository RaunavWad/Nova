//
//  NovaHeader.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit

extension AppFont {
    static func sans(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        if let n = sansName(weight) { return .custom(n, size: size, relativeTo: style) }
        return .system(size: size, weight: weight)
    }
}

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
