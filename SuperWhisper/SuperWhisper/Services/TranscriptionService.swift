import Foundation

/// HTTP client for OpenAI audio/transcriptions API with automatic retry and dynamic timeout.
class TranscriptionService {
    private let settingsService: SettingsService
    private let session: URLSession

    /// Called during retry attempts: (currentAttempt, maxAttempts).
    var onRetryAttempt: ((Int, Int) -> Void)?

    private let maxRetries = 3
    private let baseBackoffSeconds: [UInt64] = [2, 4, 8]

    init(settingsService: SettingsService, session: URLSession = .shared) {
        self.settingsService = settingsService
        self.session = session
    }

    /// Transcribes with the selected model, falls back to the model's fallback when it fails for a reason other than
    /// the key, and applies the operator's term corrections.
    func transcribe(audioFileURL: URL) async throws -> String {
        let selectedModel = settingsService.selectedModel
        let rawText: String
        do {
            rawText = try await transcribeWithRetry(audioFileURL: audioFileURL, model: selectedModel)
        } catch {
            guard let fallbackModel = selectedModel.fallbackModel, isFallbackWorthyError(error) else { throw error }
            print("⚠️ \(selectedModel.rawValue) failed (\(error.localizedDescription)); retrying on \(fallbackModel.rawValue)")
            rawText = try await transcribeWithRetry(audioFileURL: audioFileURL, model: fallbackModel)
        }
        return TranscriptionTermCorrectionService.correctOperatorTerms(in: rawText)
    }

    /// Transcribes the audio file with automatic retry for transient errors.
    private func transcribeWithRetry(audioFileURL: URL, model: TranscriptionModel) async throws -> String {
        guard let apiKey = settingsService.apiKey, !apiKey.isEmpty else {
            throw TranscriptionError.noAPIKey
        }

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionError.audioFileMissing
        }

        var lastError: Error = TranscriptionError.invalidResponse

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let backoff = baseBackoffSeconds[min(attempt - 1, baseBackoffSeconds.count - 1)]
                print("🔄 Retry attempt \(attempt + 1)/\(maxRetries) after \(backoff)s backoff...")
                onRetryAttempt?(attempt + 1, maxRetries)
                try await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            }

            do {
                return try await transcriptionCheckedForHintEcho(audioFileURL: audioFileURL, apiKey: apiKey, model: model)
            } catch {
                lastError = error

                if !isRetryableError(error) {
                    print("❌ Non-retryable error: \(error.localizedDescription)")
                    throw error
                }

                print("⚠️ Retryable error on attempt \(attempt + 1): \(error.localizedDescription)")
            }
        }

        throw lastError
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

    /// Models that take the vocabulary as a prompt can return the hint itself on audio without speech
    /// ("Termos comuns: ...", or the "context:" wrapper of gpt-4o-transcribe); that answer is redone once without the hint.
    private func transcriptionCheckedForHintEcho(audioFileURL: URL, apiKey: String, model: TranscriptionModel) async throws -> String {
        let vocabularyTerms = settingsService.vocabularyTermList
        let text = try await executeTranscription(audioFileURL: audioFileURL, apiKey: apiKey, model: model, vocabularyTerms: vocabularyTerms)
        guard !model.acceptsKeywords, !vocabularyTerms.isEmpty, Self.looksLikeHintEcho(text) else { return text }
        print("⚠️ Transcription echoed the vocabulary hint; redoing without it")
        return try await executeTranscription(audioFileURL: audioFileURL, apiKey: apiKey, model: model, vocabularyTerms: [])
    }

    /// Nothing was captured: empty, or only spaces and punctuation ("." or "…" for a silent take).
    static func hasSpokenContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.union(.decimalDigits).contains($0) }
    }

    static func looksLikeHintEcho(_ text: String) -> Bool {
        text.range(of: #"(?i)\btermos comuns\s*:|\bcommon terms\s*:|\bcontext\s*:"#, options: .regularExpression) != nil
    }

    /// Network or server failures move to the fallback model; a bad or missing key would fail there too.
    private func isFallbackWorthyError(_ error: Error) -> Bool {
        guard let transcriptionError = error as? TranscriptionError else { return true }
        switch transcriptionError {
        case .noAPIKey, .invalidAPIKey, .audioFileMissing, .fileTooLarge: return false
        case .networkError, .serverError, .invalidResponse, .timeout: return true
        }
    }

    /// Execute a single transcription request (no retry).
    private func executeTranscription(audioFileURL: URL, apiKey: String, model: TranscriptionModel,
                                      vocabularyTerms: [String]) async throws -> String {
        let language = settingsService.selectedLanguage

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // H11: Get file size without loading into memory (for timeout + validation)
        let fileAttrs = try FileManager.default.attributesOfItem(atPath: audioFileURL.path)
        let fileSizeBytes = fileAttrs[.size] as? Int64 ?? 0
        let fileSizeMB = Double(fileSizeBytes) / (1024.0 * 1024.0)
        request.timeoutInterval = 120 + (fileSizeMB * 30)

        // Pre-upload file size validation (OpenAI limit: 25 MB)
        let maxSizeBytes: Int64 = 25 * 1024 * 1024
        if fileSizeBytes > maxSizeBytes {
            throw TranscriptionError.fileTooLarge
        }

        let audioData = try Data(contentsOf: audioFileURL)

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body
        var body = Data()

        // File field
        let filename = audioFileURL.lastPathComponent
        let mimeType = mimeTypeForFile(audioFileURL)
        body.appendMultipart(boundary: boundary, name: "file", filename: filename, mimeType: mimeType, data: audioData)

        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: model.rawValue)

        if model.acceptsKeywords {
            // gpt-transcribe: `languages[]` (never together with `language`) and the vocabulary in `keywords[]`.
            // Portuguese goes with English because the operator mixes English terms ("PR", "deploy", "merge").
            let spokenLanguages = language == .portuguese ? ["pt", "en"] : (language.rawValue.isEmpty ? [] : [language.rawValue])
            for spokenLanguage in spokenLanguages {
                body.appendMultipart(boundary: boundary, name: "languages[]", value: spokenLanguage)
            }
            for vocabularyTerm in vocabularyTerms {
                body.appendMultipart(boundary: boundary, name: "keywords[]", value: vocabularyTerm)
            }
        } else {
            if !language.rawValue.isEmpty {
                body.appendMultipart(boundary: boundary, name: "language", value: language.rawValue)
            }
            let promptHint = TranscriptionVocabulary.promptHint(for: vocabularyTerms)
            if !promptHint.isEmpty {
                body.appendMultipart(boundary: boundary, name: "prompt", value: promptHint)
            }
        }

        // Response format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")

        // Chunking strategy (required for gpt-4o-transcribe-diarize with audio > 30s)
        if model.requiresChunkingStrategy {
            body.appendMultipart(boundary: boundary, name: "chunking_strategy", value: "auto")
        }

        // Close boundary
        body.append("--\(boundary)--\r\n".utf8Data)

        request.httpBody = body

        // Execute request
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw TranscriptionError.timeout
        } catch {
            throw TranscriptionError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try parseResponse(data)
        case 401:
            throw TranscriptionError.invalidAPIKey
        case 413:
            throw TranscriptionError.serverError(413, "Audio file too large. Maximum size is 25 MB.")
        case 429:
            throw TranscriptionError.serverError(429, "Rate limit exceeded. Please wait and try again.")
        default:
            let errorMessage = parseErrorMessage(data) ?? "Unknown error"
            throw TranscriptionError.serverError(httpResponse.statusCode, errorMessage)
        }
    }

    /// Determine if an error is transient and should be retried.
    private func isRetryableError(_ error: Error) -> Bool {
        if let transcriptionError = error as? TranscriptionError {
            switch transcriptionError {
            case .serverError(let code, _):
                // Retry on 5xx server errors (except 413 which is file too large)
                return code >= 500 && code < 600
            case .timeout, .networkError:
                return true
            case .noAPIKey, .invalidAPIKey, .invalidResponse, .audioFileMissing, .fileTooLarge:
                return false
            }
        }

        // Retry on URL errors (network issues)
        if error is URLError {
            return true
        }

        return false
    }

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
// M9: Safe UTF-8 encoding helper to avoid force unwraps

extension String {
    fileprivate var utf8Data: Data { Data(self.utf8) }
}

extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
        append("\(value)\r\n".utf8Data)
    }

    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8Data)
        append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        append(data)
        append("\r\n".utf8Data)
    }
}
