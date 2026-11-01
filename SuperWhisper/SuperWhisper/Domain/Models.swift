import Foundation

// MARK: - Transcription Models

/// Available OpenAI transcription models.
enum TranscriptionModel: String, CaseIterable, CustomStringConvertible, Codable {
    case gptTranscribe = "gpt-transcribe"
    case whisper1 = "whisper-1"
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"
    case gpt4oTranscribeDiarize = "gpt-4o-transcribe-diarize"

    var description: String {
        switch self {
        case .gptTranscribe: return "GPT Transcribe"
        case .whisper1: return "Whisper v1"
        case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
        case .gpt4oTranscribe: return "GPT-4o Transcribe"
        case .gpt4oTranscribeDiarize: return "GPT-4o Transcribe (Speakers)"
        }
    }

    /// Whether this model supports only JSON response format.
    var jsonResponseOnly: Bool {
        switch self {
        case .whisper1: return false
        case .gptTranscribe, .gpt4oMiniTranscribe, .gpt4oTranscribe, .gpt4oTranscribeDiarize: return true
        }
    }

    /// Whether this model requires chunking_strategy for audio > 30s.
    var requiresChunkingStrategy: Bool {
        self == .gpt4oTranscribeDiarize
    }

    /// gpt-transcribe takes the vocabulary in `keywords[]` and the languages in `languages[]`; the older models take
    /// a single `language` and the vocabulary as a `prompt` hint.
    var acceptsKeywords: Bool { self == .gptTranscribe }

    /// When this model fails for a reason other than the key, the same audio is retried on this one.
    var fallbackModel: TranscriptionModel? { self == .gptTranscribe ? .gpt4oTranscribe : nil }
}

/// Business and tech terms the transcription should spell right, from the Jarvis Voz bridge on mark2
/// (transcricao_com_gemini.VOCABULARIO_DO_OPERADOR, 31/10/2026). Only terms: example phrases in the hint came back as the
/// transcription of silent audio. Personal names and places live only in the local settings (Settings → Vocabulary),
/// never in this public repository.
enum TranscriptionVocabulary {
    static let defaultOperatorTerms = [
        "Jarvis", "Hey Jarvis", "Jarvis Voz", "SuperWhisper", "CTO", "CEO",
        "Kestra", "Kestra Agency", "DirectAds", "DirectCash", "MedyCallis", "NC Caps", "Jev", "Loot", "LootRush",
        "mark2", "mark3", "mark5", "mark7", "mark8", "mark9", "Scriptorium", "portal", "Gerente", "MultiWA",
        "PR", "pull request", "deploy", "beta", "main", "merge", "GitHub", "Railway", "Cloudflare", "DigitalOcean",
        "BM", "Meta", "Facebook Ads", "Graph API", "Direct Response", "Stripe", "Pluggy", "WhatsApp", "Whapi", "Whapi Cloud",
        "UTMify", "CAPI", "pixel", "ROAS", "CPA", "CPM", "CTR", "checkout", "top-up",
        "Claude", "Claude Code", "Haiku", "Sonnet", "Opus", "Codex", "Gemini", "tick", "ticks",
        "BetterStack", "Sentry", "NestJS", "Next.js", "Prisma", "BullMQ", "AirPods", "MacBook",
    ]

    static func terms(from commaSeparatedTerms: String) -> [String] {
        commaSeparatedTerms.split(whereSeparator: { $0 == "," || $0.isNewline }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func promptHint(for terms: [String]) -> String {
        terms.isEmpty ? "" : "Termos comuns: " + terms.joined(separator: ", ") + "."
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
    case fileTooLarge
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured. Please add your OpenAI API key in Settings."
        case .invalidAPIKey: return "Invalid API key. Please check your key in Settings."
        case .networkError(let msg): return "Network error: \(msg)"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .invalidResponse: return "Invalid response from server."
        case .audioFileMissing: return "Audio file not found."
        case .fileTooLarge: return "Audio file exceeds 25 MB limit. Try a shorter recording."
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
