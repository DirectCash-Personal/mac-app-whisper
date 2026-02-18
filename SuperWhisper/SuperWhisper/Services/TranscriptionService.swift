import Foundation

/// HTTP client for OpenAI audio/transcriptions API.
class TranscriptionService {
    private let settingsService: SettingsService
    private let session: URLSession

    init(settingsService: SettingsService, session: URLSession = .shared) {
        self.settingsService = settingsService
        self.session = session
    }

    /// Transcribes the audio file at the given URL using the OpenAI API.
    func transcribe(audioFileURL: URL) async throws -> String {
        guard let apiKey = settingsService.apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionError.audioFileMissing
        }

        let model = settingsService.selectedModel
        let language = settingsService.selectedLanguage

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // File field
        let audioData = try Data(contentsOf: audioFileURL)
        let filename = audioFileURL.lastPathComponent
        let mimeType = mimeTypeForFile(audioFileURL)

        body.appendMultipart(boundary: boundary, name: "file", filename: filename, mimeType: mimeType, data: audioData)

        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: model.rawValue)

        // Language field (if not auto)
        if !language.rawValue.isEmpty {
            body.appendMultipart(boundary: boundary, name: "language", value: language.rawValue)
        }

        // Response format
        if model.jsonResponseOnly {
            body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
        } else {
            body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
        }

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Execute request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponse(data)
        case 401:
            throw TranscriptionError.invalidAPIKey
        case 429:
            throw TranscriptionError.serverError(429, "Rate limit exceeded. Please wait and try again.")
        default:
            let errorMessage = parseErrorMessage(data) ?? "Unknown error"
            throw TranscriptionError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    /// Test API key validity by making a minimal request.
    func testAPIKey(_ key: String) async -> Bool {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {}
        return false
    }

    // MARK: - Private

    private func parseResponse(_ data: Data) throws -> String {
        let result = try JSONDecoder().decode(TranscriptionResult.self, from: data)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        struct ErrorResponse: Codable {
            struct ErrorDetail: Codable {
                let message: String
            }
            let error: ErrorDetail
        }
        return try? JSONDecoder().decode(ErrorResponse.self, from: data).error.message
    }

    private func mimeTypeForFile(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": return "audio/m4a"
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "mp4": return "audio/mp4"
        case "webm": return "audio/webm"
        case "ogg": return "audio/ogg"
        case "flac": return "audio/flac"
        default: return "audio/wav"
        }
    }
}

// MARK: - Data Extension for Multipart

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
