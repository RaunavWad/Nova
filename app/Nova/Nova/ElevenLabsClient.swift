//
//  ElevenLabsClient.swift
//  Nova
//
//  Created by Vihaan Deshmukh on 10/10/26.
//

import Foundation
import CryptoKit

// this is the text to speech through Eleven Labs

actor ElevenLabsClient {
    static let shared = ElevenLabsClient()

    struct Config: Sendable { let apiKey: String; let voiceID: String; let modelID: String }
    enum ClientError: Error { case notConfigured, badStatus(Int), empty }

    private let config: Config?
    private let cacheDir: URL

    nonisolated var isConfigured: Bool { config != nil }

    init() {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any],
           let key = dict["ELEVENLABS_API_KEY"] as? String, !key.isEmpty, !key.hasPrefix("PASTE"),
           let voice = dict["ELEVENLABS_VOICE_ID"] as? String, !voice.isEmpty, !voice.hasPrefix("PASTE") {
            config = Config(apiKey: key, voiceID: voice, modelID: (dict["ELEVENLABS_MODEL_ID"] as? String) ?? "eleven_flash_v2_5")
        } else {
            config = nil
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("ElevenLabs", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// MP3 data for `text`: from the cache if we have it, otherwise fetched (and cached).
    func speech(for text: String) async throws -> Data {
        guard let config else { throw ClientError.notConfigured }
        let clipped = String(text.prefix(4500))
        let file = cacheDir.appendingPathComponent(Self.hash(config.voiceID + "|" + config.modelID + "|" + clipped) + ".mp3")
        if let cached = try? Data(contentsOf: file), !cached.isEmpty { return cached }

        var comps = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(config.voiceID)")!
        comps.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var req = URLRequest(url: comps.url!, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["text": clipped, "model_id": config.modelID,
                                   "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw ClientError.badStatus(status) }
        guard !data.isEmpty else { throw ClientError.empty }
        try? data.write(to: file, options: .atomic)
        return data
    }

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
