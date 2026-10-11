//
//  Components.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum Theme {
    static let midnight = Color(hex: 0x080E1B)
    static let deep = Color(hex: 0x0D1628)
    static let panel = Color(hex: 0x131D30)
    static let accent = Color(hex: 0x68E1FF)
    static let violet = Color(hex: 0xB7A4FF)
    static let text = Color(hex: 0xF4F7FF)
    static let textSecondary = Color(hex: 0xA8B6CA)
    static let border = Color(hex: 0x2A3A57)
}


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


private struct PressHaptic<Content: View>: View {
    @EnvironmentObject var haptics: HapticsManager
    let isPressed: Bool
    @ViewBuilder var content: Content
    var body: some View {
        content.onChange(of: isPressed) { _, pressed in if pressed { haptics.play(.select) } }
    }
}

extension View {
    func hapticTap() -> some View { modifier(HapticTapModifier()) }
}

private struct HapticTapModifier: ViewModifier {
    @EnvironmentObject var haptics: HapticsManager
    func body(content: Content) -> some View {
        content.simultaneousGesture(TapGesture().onEnded { haptics.play(.select) })
    }
}

struct BigButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        PressHaptic(isPressed: configuration.isPressed) { configuration.label }
            .font(AppFont.style(.title3, .semibold))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .foregroundStyle(prominent ? Theme.midnight : Theme.text)
            .background {
                if prominent {
                    shape.fill(LinearGradient(colors: [Theme.accent, Color(hex: 0x4FC8EA)], startPoint: .top, endPoint: .bottom))
                } else {
                    shape.fill(LinearGradient(colors: [Theme.panel, Theme.panel.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(shape.stroke(prominent ? Color.white.opacity(0.25) : Theme.border, lineWidth: prominent ? 1 : 1.2))
            .shadow(color: prominent ? Theme.accent.opacity(0.28) : .clear, radius: 14, y: 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.style(.headline, .semibold)).foregroundStyle(Theme.text)
                if let subtitle {
                    Text(subtitle).font(AppFont.style(.subheadline)).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary).accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        PressHaptic(isPressed: configuration.isPressed) { configuration.label }
            .background(shape.fill(LinearGradient(colors: [Theme.panel, Theme.panel.opacity(0.78)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.stroke(Theme.border, lineWidth: 1.2))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// this is for liquid glass!!!

extension View {
    @ViewBuilder func novaGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Theme.border, lineWidth: 1))
        }
        #else
        self.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(Theme.border, lineWidth: 1))
        #endif
    }
}

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
            .background(LinearGradient(colors: [Theme.panel, Theme.panel.opacity(0.8)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}


struct Screen<Content: View>: View {
    let title: String
    var showsTitle = true
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
        .navigationBarTitleDisplayMode(showsTitle ? .large : .inline)
        .toolbar(showsTitle ? .automatic : .hidden, for: .navigationBar)
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
