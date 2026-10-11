//
//  ChatManager.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Combine
import Foundation

@MainActor
final class ChatManager: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    enum Phase: Equatable { case idle, listening, transcribing, thinking, speaking }
    struct Turn: Identifiable { let id = UUID(); let isUser: Bool; let text: String }

    private(set) var turns: [Turn] = [] { willSet { objectWillChange.send() } }
    private(set) var phase: Phase = .idle { willSet { objectWillChange.send() } }
    private(set) var errorText: String? = nil { willSet { objectWillChange.send() } }

    let recorder = VoiceRecorder()
    private let speech: SpeechManager
    private let location: LocationManager

    var isConfigured: Bool { ClaudeClient.configurationProblem == nil }
    var setupProblem: String? { ClaudeClient.configurationProblem }

    init(speech: SpeechManager, location: LocationManager) {
        self.speech = speech
        self.location = location
        recorder.onAutoStop = { [weak self] in Task { @MainActor in await self?.finishListening() } }
    }

    private var systemPrompt: String {
        let f = DateFormatter(); f.dateStyle = .full; f.timeStyle = .short
        let moon = AstronomyEngine.moonPhase(date: Date())
        let place = location.placeName.map { "The person is near \($0)." } ?? ""
        return """
        You are Nova, a warm, patient astronomy guide inside an app for blind and visually impaired people. \
        Your answers are read aloud, so write plain spoken sentences: no lists, no markdown, no symbols, no emoji. \
        Keep answers short, usually two to four sentences, and describe things through size, distance, sound and touch comparisons rather than colors or pictures alone. \
        Be accurate. If you are unsure, say so. You cannot see the sky or the person's surroundings, so never claim you can; \
        for what is overhead right now, point them to Nova's Explore and Find tabs, which calculate positions from their location and the time. \
        It is \(f.string(from: Date())). The Moon is \(moon.name), about \(Int((moon.fraction * 100).rounded())) percent lit. \(place)
        """
    }


    func toggleListening() async {
        switch phase {
        case .listening: await finishListening()
        case .idle:
            speech.stop()
            errorText = nil
            do {
                try await recorder.requestPermission()
                try recorder.start()
                phase = .listening
            } catch {
                fail(error.localizedDescription)
            }
        default:
            speech.stop(); phase = .idle
        }
    }

    func finishListening() async {
        guard phase == .listening else { return }
        guard let file = recorder.stop() else { phase = .idle; return }
        phase = .transcribing
        do {
            let text = try await ElevenLabsClient.shared.transcribe(fileURL: file)
            recorder.discard()
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { fail("I didn't hear anything. Tap the button and try again."); return }
            await ask(cleaned)
        } catch {
            recorder.discard()
            fail(error.localizedDescription)
        }
    }


    func ask(_ question: String) async {
        errorText = nil
        turns.append(Turn(isUser: true, text: question))
        phase = .thinking
        let history = turns.suffix(8).map { ClaudeClient.Message(role: $0.isUser ? "user" : "assistant", content: $0.text) }
        do {
            let answer = try await ClaudeClient.shared.reply(to: Array(history), system: systemPrompt)
            turns.append(Turn(isUser: false, text: answer))
            phase = .speaking
            speech.narrate(answer)
            phase = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    func clear() { speech.stop(); turns = []; errorText = nil; phase = .idle }

    private func fail(_ message: String) {
        errorText = message
        phase = .idle
        speech.announce(message)
    }
}
