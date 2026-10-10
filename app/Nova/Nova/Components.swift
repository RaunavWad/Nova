//
//  Components.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI
import Combine

// MARK: - Theme

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let midnight = Color(hex: 0x080E1B)        // main background: deep space navy
    static let deep = Color(hex: 0x0D1628)            // slight lift used in the background gradient
    static let panel = Color(hex: 0x131D30)           // cards / panels: raised navy
    static let accent = Color(hex: 0x68E1FF)          // primary accent: stellar cyan
    static let violet = Color(hex: 0xB7A4FF)          // secondary accent: soft violet (achievements, highlights)
    static let text = Color(hex: 0xF4F7FF)            // main text: starlight white
    static let textSecondary = Color(hex: 0xA8B6CA)   // secondary text: muted blue-gray
    static let border = Color(hex: 0x2A3A57)          // borders / dividers: slate blue (hex not specified; chosen to suit)
}

// MARK: - Background (decorative only; hidden from VoiceOver)

struct StarfieldBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, phase: Double)] = {
        var g = SystemRandomNumberGenerator()
        return (0..<110).map { _ in (CGFloat.random(in: 0...1, using: &g), CGFloat.random(in: 0...1, using: &g),
                                      CGFloat.random(in: 0.5...1.8, using: &g), Double.random(in: 0...6.28, using: &g)) }
    }()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.midnight, Theme.deep, Theme.midnight], startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: reduceMotion ? nil : 1.0 / 12.0, paused: reduceMotion)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for s in stars {
                        let twinkle = reduceMotion ? 0.8 : 0.55 + 0.35 * sin(t * 0.8 + s.phase)
                        let rect = CGRect(x: s.x * size.width, y: s.y * size.height, width: s.r, height: s.r)
                        ctx.fill(Path(ellipseIn: rect), with: .color(Theme.text.opacity(twinkle)))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Controls

/// Large, high-contrast button with a clear label. Fires a haptic tick (the "select" pattern) when pressed.
struct BigButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.style(.title3, .semibold))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .foregroundStyle(prominent ? Theme.midnight : Theme.text)
            .background(prominent ? Theme.accent : Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: prominent ? 0 : 1.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Button with the app's haptic tick built in.
struct AppButton: View {
    @EnvironmentObject var haptics: HapticsManager
    let title: String
    var systemImage: String? = nil
    var prominent = true
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            haptics.play(.select)
            action()
        } label: {
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
        }
        .buttonStyle(BigButtonStyle(prominent: prominent))
        .accessibilityHint(hint ?? "")
    }
}

/// Repeat / Pause / Stop for narration. Present wherever speech can run long.
struct SpeechControls: View {
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var audio: AudioManager

    var body: some View {
        ViewThatFits {
            HStack(spacing: 10) { buttons }
            VStack(spacing: 10) { buttons }
        }
    }

    @ViewBuilder private var buttons: some View {
        AppButton(title: "Repeat", systemImage: "arrow.counterclockwise", prominent: false,
                  hint: "Hear the last thing said again") { speech.repeatLast() }
        AppButton(title: speech.isPaused ? "Resume" : "Pause", systemImage: speech.isPaused ? "play.fill" : "pause.fill",
                  prominent: false, hint: "Pause or resume narration") { speech.isPaused ? speech.resume() : speech.pause() }
        AppButton(title: "Stop", systemImage: "stop.fill", prominent: false, hint: "Stop narration") { speech.stop() }
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

/// Screen scaffold: starfield, scrolling content, readable width, starlight tint.
struct Screen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            StarfieldBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .font(AppFont.style(.body))
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func sectionHeader() -> some View {
        self.font(AppFont.style(.headline, .semibold)).foregroundStyle(Theme.accent).accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Demo controls (clearly simulated)

struct DemoControls: View {
    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var persistence: PersistenceManager
    var target: Horizontal? = nil

    var body: some View {
        if persistence.settings.demoMode {
            Panel {
                Text("Demo mode: simulated pointing").sectionHeader()
                Text("No real sensors are used. Set a pretend pointing direction below. Real mode is in Settings.")
                    .font(AppFont.style(.subheadline))
                let p = motion.simulatedPointing
                Stepper("Aim left or right: \(Int(p.azimuth)) degrees compass", onIncrement: {
                    motion.setSimulated(azimuth: p.azimuth + 5, altitude: p.altitude)
                }, onDecrement: {
                    motion.setSimulated(azimuth: p.azimuth - 5, altitude: p.altitude)
                })
                Stepper("Aim up or down: \(Int(p.altitude)) degrees high", onIncrement: {
                    motion.setSimulated(azimuth: p.azimuth, altitude: p.altitude + 5)
                }, onDecrement: {
                    motion.setSimulated(azimuth: p.azimuth, altitude: p.altitude - 5)
                })
                if let t = target {
                    AppButton(title: "Aim exactly at the target (demo)", systemImage: "scope", prominent: false) {
                        motion.setSimulated(azimuth: t.azimuth, altitude: t.altitude)
                    }
                }
            }
        }
    }
}
