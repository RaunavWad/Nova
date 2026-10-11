//
//  AskView.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import SwiftUI

struct AskView: View {
    @EnvironmentObject var chat: ChatManager
    @EnvironmentObject var speech: SpeechManager
    @EnvironmentObject var haptics: HapticsManager
    @State private var typed = ""
    @FocusState private var typing: Bool

    private var statusText: String {
        switch chat.phase {
        case .idle: return "Tap and ask anything about space"
        case .listening: return "Listening… tap again when done"
        case .transcribing: return "Understanding your question…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        }
    }

    var body: some View {
        Screen(title: "Ask Nova") {
            if let problem = chat.setupProblem {
                Panel {
                    Label("Assistant not set up", systemImage: "exclamationmark.triangle").font(AppFont.style(.headline, .semibold))
                    Text(problem).font(AppFont.style(.subheadline))
                }
                .accessibilityElement(children: .combine)
            }

            Button {
                haptics.play(.select)
                typing = false
                Task { await chat.toggleListening() }
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: chat.phase == .listening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 64))
                    Text(statusText).font(AppFont.style(.headline, .semibold)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
            }
            .buttonStyle(BigButtonStyle(prominent: true))
            .disabled(chat.phase == .transcribing || chat.phase == .thinking)
            .accessibilityLabel(chat.phase == .listening ? "Stop listening and send" : "Ask a question by voice")
            .accessibilityHint("Tap, speak your question, and Nova will say the answer out loud.")

            HStack(spacing: 10) {
                TextField("Or type a question", text: $typed)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(sendTyped)
                    .padding(12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button("Send", action: sendTyped)
                    .buttonStyle(BigButtonStyle(prominent: false))
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty || chat.phase != .idle)
            }

            if let e = chat.errorText {
                Text(e).font(AppFont.style(.subheadline)).foregroundStyle(Theme.violet)
            }

            ForEach(chat.turns.reversed()) { turn in
                Panel {
                    Text(turn.isUser ? "You asked" : "Nova")
                        .font(AppFont.style(.subheadline, .semibold)).foregroundStyle(Theme.textSecondary)
                    Text(turn.text).font(AppFont.style(.body))
                    if !turn.isUser {
                        Button("Hear it again") { speech.narrate(turn.text) }.hapticTap()
                    }
                }
                .accessibilityElement(children: .contain)
            }

            if !chat.turns.isEmpty {
                AppButton(title: "Start over", systemImage: "arrow.counterclockwise", prominent: false) { chat.clear() }
            }

            Text("Your question is turned into text by ElevenLabs and answered by OpenRouter. The recording is deleted right after. Your location is shared only as a town name, to help answers. Nova can make mistakes, so check anything important.")
                .font(AppFont.style(.footnote)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func sendTyped() {
        let q = typed.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, chat.phase == .idle else { return }
        typed = ""; typing = false
        Task { await chat.ask(q) }
    }
}
