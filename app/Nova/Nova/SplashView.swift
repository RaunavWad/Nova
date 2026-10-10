//
//  SplashView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import UIKit

/// Launch animation: a ring draws in around a star, a small moon orbits, the name fades up. About 2.6 seconds
/// (longer when VoiceOver is on so the name can be read). Tap anywhere to skip. With Reduce Motion on, it is a
/// calm fade with no movement. The sound is the same "star" chime used in the app.
struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var audio: AudioManager

    @State private var ringTrim: CGFloat = 0
    @State private var ringScale: CGFloat = 0.85
    @State private var starScale: CGFloat = 0.5
    @State private var starOpacity = 0.0
    @State private var glow = 0.0
    @State private var orbit = 0.0
    @State private var titleOpacity = 0.0
    @State private var titleOffset: CGFloat = 14
    @State private var tagOpacity = 0.0
    @State private var finished = false

    var body: some View {
        ZStack {
            StarfieldBackground()
            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: ringTrim)
                        .stroke(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 168, height: 168)
                        .scaleEffect(ringScale)
                    Circle().fill(Theme.violet)
                        .frame(width: 11, height: 11)
                        .shadow(color: Theme.violet.opacity(0.8), radius: 6)
                        .offset(y: -84)
                        .rotationEffect(.degrees(orbit))
                        .opacity(ringTrim > 0.95 ? 1 : 0)
                    NovaMark(size: 104)
                        .shadow(color: Theme.accent.opacity(glow), radius: 22)
                        .scaleEffect(starScale)
                        .opacity(starOpacity)
                }
                .frame(height: 180)

                VStack(spacing: 10) {
                    Text("nova")
                        .font(AppFont.sans(size: 60, weight: .bold, relativeTo: .largeTitle))
                        .tracking(-2.5)
                        .foregroundStyle(Theme.text)
                        .opacity(titleOpacity)
                        .offset(y: titleOffset)
                    Text("The universe is for everyone.")
                        .font(AppFont.style(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .opacity(tagOpacity)
                }
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nova. The universe is for everyone.")
        .accessibilityHint("Opens automatically. Double tap to continue now.")
        .accessibilityAddTraits(.isButton)
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            withAnimation(.easeIn(duration: 0.5)) {
                ringTrim = 1; ringScale = 1; starScale = 1; starOpacity = 1; glow = 0.5
                titleOpacity = 1; titleOffset = 0; tagOpacity = 1
            }
            audio.play(.star)
            try? await Task.sleep(nanoseconds: UIAccessibility.isVoiceOverRunning ? 3_500_000_000 : 1_600_000_000)
            finish()
            return
        }
        audio.play(.star)
        withAnimation(.easeOut(duration: 1.1)) { ringTrim = 1; ringScale = 1 }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.65).delay(0.25)) { starScale = 1; starOpacity = 1 }
        withAnimation(.easeInOut(duration: 1.4).delay(0.3)) { glow = 0.85 }
        withAnimation(.linear(duration: 3.0)) { orbit = 360 }
        try? await Task.sleep(nanoseconds: 700_000_000)
        withAnimation(.easeOut(duration: 0.8)) { titleOpacity = 1; titleOffset = 0 }
        try? await Task.sleep(nanoseconds: 500_000_000)
        withAnimation(.easeOut(duration: 0.7)) { tagOpacity = 1 }
        try? await Task.sleep(nanoseconds: UIAccessibility.isVoiceOverRunning ? 3_000_000_000 : 1_000_000_000)
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
