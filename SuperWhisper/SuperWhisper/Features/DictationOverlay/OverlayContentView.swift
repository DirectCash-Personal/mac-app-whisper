import SwiftUI

/// SwiftUI content for the dictation overlay — switches between Recording/Processing/Success states.
struct OverlayContentView: View {
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var settingsService: SettingsService

    var body: some View {
        ZStack {
            // Transparent background (vibrancy comes from NSVisualEffectView)
            Color.clear

            switch appState.currentState {
            case .recording:
                RecordingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .processing:
                ProcessingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .success:
                SuccessView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

            case .error(let message):
                ErrorOverlayView(message: message)
                    .transition(.opacity)

            default:
                EmptyView()
            }
        }
        .frame(width: 360, height: 80)
        .animation(AppAnimation.spring, value: appState.currentState)
    }
}

/// Recording state — waveform + timer + cancel/send buttons.
/// Matches Stitch "Recording Overlay (Active State)" screen.
struct RecordingView: View {
    @EnvironmentObject var appState: AppStateManager

    var formattedDuration: String {
        let minutes = Int(appState.recordingDuration) / 60
        let seconds = Int(appState.recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Waveform
            WaveformView(
                amplitudes: appState.waveformAmplitudes,
                barCount: 16,
                isAnimating: true
            )
            .frame(width: 100, height: 40)

            // Timer
            Text(formattedDuration)
                .font(AppTypography.timer)
                .foregroundColor(AppColors.textPrimary)
                .monospacedDigit()

            Spacer()

            // Cancel & Send buttons
            HStack(spacing: AppSpacing.md) {
                // Cancel button — discards audio, does NOT send to OpenAI
                VStack(spacing: 4) {
                    Button(action: {
                        NotificationCenter.default.post(name: .cancelRecording, object: nil)
                    }) {
                        ZStack {
                            Circle()
                                .fill(AppColors.error)
                                .frame(width: 40, height: 40)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                        }
                    }
                    .buttonStyle(.plain)

                    Text("Cancel")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textTertiary)
                }

                // Send button — stops recording and sends audio to OpenAI
                VStack(spacing: 4) {
                    Button(action: {
                        NotificationCenter.default.post(name: .stopRecording, object: nil)
                    }) {
                        ZStack {
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 40, height: 40)

                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Text("Send")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
    }
}

/// Processing state — spinner + "Transcribing…".
/// Matches Stitch "Processing Overlay" screen.
struct ProcessingView: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ProgressView()
                .controlSize(.regular)
                .tint(AppColors.accent)

            Text("Transcribing…")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)
        }
    }
}

/// Success state — checkmark + "Text pasted ✓".
/// Matches Stitch "Success Overlay" screen.
struct SuccessView: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(AppColors.success)

            Text("Text pasted ✓")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)
        }
    }
}

/// Error overlay state — auto-dismisses after 5 seconds, with a close button.
struct ErrorOverlayView: View {
    let message: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(AppColors.error)

            Text(message)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)

            Spacer()

            Button(action: {
                NotificationCenter.default.post(name: .dismissOverlay, object: nil)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.lg)
        .onAppear {
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                NotificationCenter.default.post(name: .dismissOverlay, object: nil)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let stopRecording = Notification.Name("com.superwhisper.stopRecording")
    static let cancelRecording = Notification.Name("com.superwhisper.cancelRecording")
    static let dismissOverlay = Notification.Name("com.superwhisper.dismissOverlay")
}
