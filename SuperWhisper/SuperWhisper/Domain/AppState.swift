import SwiftUI
import Combine

/// Central app state machine managing the dictation flow.
/// States: idle → recording → processing → success → idle
///         idle → error → idle
///         idle → permissionsNeeded
enum DictationState: Equatable {
    case idle
    case recording
    case processing
    case success
    case error(String)
    case permissionsNeeded

    static func == (lhs: DictationState, rhs: DictationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording),
             (.processing, .processing), (.success, .success),
             (.permissionsNeeded, .permissionsNeeded):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Observable app state manager used as the single source of truth.
class AppStateManager: ObservableObject {
    @Published var currentState: DictationState = .idle
    @Published var waveformAmplitudes: [Float] = []
    @Published var recordingDuration: TimeInterval = 0
    @Published var transcribedText: String = ""
    @Published var errorMessage: String?

    func transition(to newState: DictationState) {
        // Validate transitions
        let valid: Bool
        switch (currentState, newState) {
        case (.idle, .recording),
             (.idle, .permissionsNeeded),
             (.idle, .error),
             (.recording, .processing),
             (.recording, .idle),        // cancel
             (.processing, .success),
             (.processing, .error),
             (.success, .idle),
             (.error, .idle),
             (.permissionsNeeded, .idle),
             (.permissionsNeeded, .recording):
            valid = true
        default:
            valid = false
        }

        guard valid else {
            print("⚠️ Invalid state transition: \(currentState) → \(newState)")
            return
        }

        // Reset state on certain transitions
        switch newState {
        case .idle:
            waveformAmplitudes = []
            recordingDuration = 0
            errorMessage = nil
        case .recording:
            transcribedText = ""
            waveformAmplitudes = []
            recordingDuration = 0
        case .error(let message):
            errorMessage = message
        default:
            break
        }

        currentState = newState
    }

    var isRecording: Bool { currentState == .recording }
    var isProcessing: Bool { currentState == .processing }
    var isSuccess: Bool { currentState == .success }
}
