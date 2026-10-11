//
//  ElevenLabsClient.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation
import CryptoKit


actor ElevenLabsClient {
    static let shared = ElevenLabsClient()

    struct Config: Sendable { let apiKey: String; let voiceID: String; let modelID: String }

    enum ClientError: Error, LocalizedError {
        case notConfigured
        case api(status: Int, message: String)
        case empty

        var errorDescription: String? {
            switch self {
            case .notConfigured: return ElevenLabsClient.configurationProblem ?? "Premium voice is not set up."
            case .empty: return "ElevenLabs sent back no audio."
            case .api(let status, let message): return ElevenLabsClient.explain(status: status, message: message)
            }
        }
    }

    private let config: Config?
    private let cacheDir: URL

    nonisolated var isConfigured: Bool { config != nil }

    init() {
        config = Self.loadConfig()
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("ElevenLabs", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }


    private static func secrets() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist") else { return nil }
        return NSDictionary(contentsOf: url) as? [String: Any]
    }

    private static func clean(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
              !s.uppercased().hasPrefix("PASTE") else { return nil }
        return s
    }

    private static func loadConfig() -> Config? {
        guard let dict = secrets(), let key = clean(dict["ELEVENLABS_API_KEY"]), let voice = clean(dict["ELEVENLABS_VOICE_ID"]) else { return nil }
        return Config(apiKey: key, voiceID: voice, modelID: clean(dict["ELEVENLABS_MODEL_ID"]) ?? "eleven_flash_v2_5")
    }

    nonisolated static var configurationProblem: String? {
        guard let dict = secrets() else {
            return "Secrets.plist isn't inside the app. In Xcode, drag Secrets.plist into the Nova folder and tick the Nova target (it must also appear under Build Phases > Copy Bundle Resources)."
        }
        if clean(dict["ELEVENLABS_API_KEY"]) == nil { return "Secrets.plist has no ELEVENLABS_API_KEY value." }
        if clean(dict["ELEVENLABS_VOICE_ID"]) == nil { return "Secrets.plist has no ELEVENLABS_VOICE_ID value." }
        return nil
    }

    func speech(for text: String) async throws -> Data {
        guard let config else { throw ClientError.notConfigured }
        let clipped = String(text.prefix(4500))
        let file = cacheDir.appendingPathComponent(Self.hash(config.voiceID + "|" + config.modelID + "|" + clipped) + ".mp3")
        if let cached = try? Data(contentsOf: file), !cached.isEmpty { return cached }

        var comps = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(config.voiceID)")!
        comps.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var req = URLRequest(url: comps.url!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["text": clipped, "model_id": config.modelID,
                                   "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw ClientError.api(status: status, message: Self.apiMessage(from: data)) }
        guard !data.isEmpty else { throw ClientError.empty }
        try? data.write(to: file, options: .atomic)
        return data
    }

    nonisolated func isCached(_ text: String) -> Bool {
        guard let config else { return false }
        let clipped = String(text.prefix(4500))
        let file = cacheDir.appendingPathComponent(Self.hash(config.voiceID + "|" + config.modelID + "|" + clipped) + ".mp3")
        return FileManager.default.fileExists(atPath: file.path)
    }

    func prefetch(_ text: String) async { _ = try? await speech(for: text) }

    func check() async -> String {
        guard config != nil else { return Self.configurationProblem ?? "Premium voice is not set up." }
        do {
            _ = try await speech(for: "Nova premium voice is working.")
            return "Premium voice is working."
        } catch let e as ClientError {
            return e.errorDescription ?? "Premium voice failed."
        } catch let e as URLError {
            return "Couldn't reach ElevenLabs (\(e.localizedDescription)). Check the internet connection."
        } catch {
            return "Premium voice failed: \(error.localizedDescription)"
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        if let e = error as? ClientError { return e.errorDescription ?? "Premium voice failed." }
        if let e = error as? URLError { return "Couldn't reach ElevenLabs (\(e.localizedDescription))." }
        return "Premium voice failed: \(error.localizedDescription)"
    }

    func transcribe(fileURL: URL) async throws -> String {
        guard let config else { throw ClientError.notConfigured }
        let audio = try Data(contentsOf: fileURL)
        guard audio.count > 1500 else { throw ClientError.api(status: 0, message: "That recording was too short to hear.") }
        let boundary = "nova-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model_id", Self.secretValue("ELEVENLABS_STT_MODEL_ID") ?? "scribe_v1")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"question.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!, timeoutInterval: 45)
        req.httpMethod = "POST"
        req.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw ClientError.api(status: status, message: Self.apiMessage(from: data)) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ClientError.api(status: 0, message: "I couldn't hear any words in that recording.")
        }
        return text
    }

    nonisolated static func secretValue(_ key: String) -> String? { clean(secrets()?[key]) }

    private static func apiMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let detail = json["detail"] as? [String: Any] {
            return (detail["message"] as? String) ?? (detail["status"] as? String) ?? ""
        }
        return (json["detail"] as? String) ?? (json["message"] as? String) ?? ""
    }

    nonisolated static func explain(status: Int, message: String) -> String {
        let extra = message.isEmpty ? "" : " ElevenLabs said: \(message)"
        if status == 0 { return message }
        switch status {
        case 422: return "ElevenLabs rejected the request (422)." + extra
        case 429: return "ElevenLabs says too many requests or no credits left (429)." + extra
        default: return "ElevenLabs returned error \(status)." + extra
        }
    }

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
