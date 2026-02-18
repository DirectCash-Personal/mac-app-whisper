import Foundation

// MARK: - Transcription Models

/// Available OpenAI transcription models.
enum TranscriptionModel: String, CaseIterable, CustomStringConvertible, Codable {
    case whisper1 = "whisper-1"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"

    var description: String {
        switch self {
        case .whisper1: return "Whisper v1"
        case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
        case .gpt4oTranscribe: return "GPT-4o Transcribe"
        }
    }

    /// Whether this model supports only JSON response format.
    var jsonResponseOnly: Bool {
        switch self {
        case .whisper1: return false
        case .gpt4oMiniTranscribe, .gpt4oTranscribe: return true
        }
    }
}

/// Available languages for transcription.
enum TranscriptionLanguage: String, CaseIterable, CustomStringConvertible, Codable {
    case auto = ""
    case english = "en"
    case portuguese = "pt"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case japanese = "ja"
    case chinese = "zh"

    var description: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .portuguese: return "Portuguese"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .chinese: return "Chinese"
        }
    }
}

// MARK: - Transcription Result

struct TranscriptionResult: Codable {
    let text: String
}

// MARK: - Transcription Error

enum TranscriptionError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case networkError(String)
    case serverError(Int, String)
    case invalidResponse
    case audioFileMissing
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Please add your OpenAI API key in Settings."
        case .invalidAPIKey: return "Invalid API key. Please check your key in Settings."
        case .networkError(let msg): return "Network error: \(msg)"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .invalidResponse: return "Invalid response from server."
        case .audioFileMissing: return "Audio file not found."
        case .timeout: return "Request timed out. Please try again."
        }
    }
}

// MARK: - Audio Error

enum AudioError: LocalizedError {
    case microphoneNotAvailable
    case permissionDenied
    case engineStartFailed(String)
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneNotAvailable: return "Microphone not available."
        case .permissionDenied: return "Microphone permission denied."
        case .engineStartFailed(let msg): return "Audio engine failed: \(msg)"
        case .recordingFailed(let msg): return "Recording failed: \(msg)"
        }
    }
}

// MARK: - Permission Status

struct PermissionStatus {
    let isGranted: Bool
    let title: String
    let description: String
    let isRequired: Bool
}
