//
//  ClaudeClient.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation


actor ClaudeClient {
    static let shared = ClaudeClient()

    struct Message: Sendable { let role: String; let content: String }

    enum ClientError: Error, LocalizedError {
        case notConfigured
        case api(status: Int, message: String)
        case empty

        var errorDescription: String? {
            switch self {
            case .notConfigured: return ClaudeClient.configurationProblem ?? "The assistant is not set up."
            case .empty: return "The assistant sent back an empty answer."
            case .api(let status, let message):
                let extra = message.isEmpty ? "" : " It said: \(message)"
                switch status {
                case 401: return "Anthropic rejected the API key (401). Check ANTHROPIC_API_KEY in Secrets.plist." + extra
                case 404: return "Anthropic doesn't know that model name (404). Check ANTHROPIC_MODEL_ID in Secrets.plist." + extra
                case 429: return "Anthropic says too many requests or no credit left (429)." + extra
                case 529, 503: return "Anthropic is busy right now. Try again in a moment." + extra
                default: return "Anthropic returned error \(status)." + extra
                }
            }
        }
    }

    private let apiKey: String
    private let model: String
    private let useOpenRouter: Bool

    nonisolated var isConfigured: Bool { apiKey != nil }

    init() {
        if let k = ElevenLabsClient.secretValue("OPENROUTER_API_KEY") {
            apiKey = k; useOpenRouter = true
            model = ElevenLabsClient.secretValue("OPENROUTER_MODEL_ID") ?? "openrouter/auto"
        } else {
            apiKey = ElevenLabsClient.secretValue("ANTHROPIC_API_KEY"); useOpenRouter = false
            model = ElevenLabsClient.secretValue("ANTHROPIC_MODEL_ID") ?? "claude-haiku-5-5"
        }
    }

    nonisolated static var configurationProblem: String? {
        (ElevenLabsClient.secretValue("ANTHROPIC_API_KEY") == nil && ElevenLabsClient.secretValue("OPENROUTER_API_KEY") == nil)
            ? "Secrets.plist has no OPENROUTER_API_KEY (openrouter.ai/keys) or ANTHROPIC_API_KEY value. Add one and make sure Secrets.plist is inside the app."
            : nil
    }

    func reply(to messages: [Message], system: String) async throws -> String {
        guard let apiKey else { throw ClientError.notConfigured }
        if useOpenRouter { return try await replyOpenRouter(apiKey: apiKey, messages: messages, system: system) }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 40)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 500,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw ClientError.api(status: status, message: message)
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.empty }
        return text
    }

    private func replyOpenRouter(apiKey: String, messages: [Message], system: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, timeoutInterval: 40)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Nova", forHTTPHeaderField: "X-Title")
        var msgs: [[String: String]] = [["role": "system", "content": system]]
        msgs += messages.map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = ["model": model, "max_tokens": 500, "messages": msgs]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw ClientError.api(status: status, message: message)
        }
        let choice = (json?["choices"] as? [[String: Any]])?.first
        let text = ((choice?["message"] as? [String: Any])?["content"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.empty }
        return text
    }
}
