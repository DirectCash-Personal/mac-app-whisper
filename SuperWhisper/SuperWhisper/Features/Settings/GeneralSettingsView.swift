import SwiftUI

/// General settings tab — API key, model, language, behavior toggles.
/// Matches Stitch "General Settings - SuperWhisper" screen.
struct GeneralSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @State private var apiKeyInput: String = ""
    @State private var isTestingKey: Bool = false
    @State private var keyTestResult: KeyTestResult?
    @State private var isKeySaved: Bool = false
    @State private var isEditing: Bool = false

    enum KeyTestResult {
        case valid, invalid
    }

    /// Whether the user already has a saved API key and is NOT editing
    private var hasStoredKey: Bool {
        settingsService.hasAPIKey && !isEditing
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: AppSpacing.xl) {
                // API Connection Section
                SectionCard(title: "API Connection", icon: "key.fill") {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Configure your OpenAI API key for transcription services.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textTertiary)

                        if hasStoredKey {
                            // Saved state — show masked key + Change button
                            HStack(spacing: AppSpacing.md) {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(AppColors.success)
                                    Text("API Key saved securely")
                                        .font(AppTypography.body)
                                        .foregroundColor(AppColors.textPrimary)
                                }

                                Spacer()

                                SecondaryButton("Change API Key", icon: "pencil") {
                                    isEditing = true
                                    apiKeyInput = settingsService.apiKey ?? ""
                                    isKeySaved = false
                                    keyTestResult = nil
                                }
                            }
                        } else {
                            // Editing / new key state
                            SecureInputField(
                                label: "API Key",
                                placeholder: "sk-...",
                                text: $apiKeyInput
                            )

                            HStack(spacing: AppSpacing.md) {
                                PrimaryButton(
                                    isKeySaved ? "✓ Saved" : "Save Key",
                                    icon: isKeySaved ? nil : "checkmark",
                                    isDisabled: apiKeyInput.isEmpty
                                ) {
                                    settingsService.apiKey = apiKeyInput
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isKeySaved = true
                                    }
                                    // After a moment, switch to stored view
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        withAnimation {
                                            isEditing = false
                                        }
                                    }
                                }

                                SecondaryButton("Test Key", icon: "bolt.fill") {
                                    testAPIKey()
                                }

                                if isTestingKey {
                                    ProgressView()
                                        .controlSize(.small)
                                }

                                Spacer()

                                if let result = keyTestResult {
                                    HStack(spacing: AppSpacing.xs) {
                                        Image(systemName: result == .valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        Text(result == .valid ? "Key is valid" : "Key is invalid")
                                    }
                                    .font(AppTypography.caption)
                                    .foregroundColor(result == .valid ? AppColors.success : AppColors.error)
                                }

                                // Cancel editing if already had a key
                                if settingsService.hasAPIKey {
                                    Button("Cancel") {
                                        withAnimation {
                                            isEditing = false
                                        }
                                    }
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textTertiary)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                // Transcription Section
                SectionCard(title: "Transcription", icon: "translate") {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("Select the AI model and language preferences.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textTertiary)

                        HStack(spacing: AppSpacing.lg) {
                            DropdownField(
                                label: "Model",
                                options: TranscriptionModel.allCases,
                                selection: $settingsService.selectedModel
                            )

                            DropdownField(
                                label: "Language",
                                options: TranscriptionLanguage.allCases,
                                selection: $settingsService.selectedLanguage
                            )
                        }
                    }
                }

                // Behavior Section
                SectionCard(title: "Behavior", icon: "tune") {
                    VStack(spacing: AppSpacing.sm) {
                        Text("Customize how the app reacts after recording.")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider().opacity(0.2)

                        ToggleRow(
                            "Auto-paste after transcription",
                            description: "Automatically paste text into your active app",
                            icon: "doc.on.clipboard",
                            isOn: $settingsService.autoPasteEnabled
                        )

                        ToggleRow(
                            "Show notification",
                            description: "Display a notification when transcription is complete",
                            icon: "bell.badge",
                            isOn: $settingsService.showNotification
                        )

                        ToggleRow(
                            "Play sound on completion",
                            description: "Play a subtle sound when done",
                            icon: "speaker.wave.2",
                            isOn: $settingsService.playSoundOnCompletion
                        )
                    }
                }

                // Bottom padding so content isn't cut off
                Spacer().frame(height: AppSpacing.xl)
            }
            .padding(AppSpacing.xl)
        }
        .onAppear {
            apiKeyInput = settingsService.apiKey ?? ""
            isEditing = !settingsService.hasAPIKey
        }
    }

    private func testAPIKey() {
        isTestingKey = true
        keyTestResult = nil

        let service = TranscriptionService(settingsService: settingsService)
        Task {
            let isValid = await service.testAPIKey(apiKeyInput)
            await MainActor.run {
                isTestingKey = false
                keyTestResult = isValid ? .valid : .invalid
            }
        }
    }
}
