import SwiftUI

/// Permissions onboarding screen — matched to Stitch "SuperWhisper Permissions Onboarding" screen.
struct PermissionsView: View {
    @EnvironmentObject var permissionsService: PermissionsService
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            // App icon
            ZStack {
                Circle()
                    .fill(AppColors.accentGradient)
                    .frame(width: 64, height: 64)
                    .shadow(color: AppColors.accent.opacity(0.3), radius: 16)

                Image(systemName: "waveform")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.top, AppSpacing.xxl)

            // Title
            VStack(spacing: AppSpacing.sm) {
                Text("SuperWhisper needs your permission")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("These permissions are required for the app to function properly.")
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Permission cards
            VStack(spacing: AppSpacing.md) {
                PermissionCard(
                    title: "Microphone Access",
                    description: "Required to capture your voice for transcription",
                    icon: "mic.fill",
                    isGranted: permissionsService.microphoneStatus,
                    isRequired: true,
                    onOpenSettings: {
                        permissionsService.requestMicrophonePermission { _ in
                            permissionsService.refreshStatus()
                        }
                    }
                )

                PermissionCard(
                    title: "Accessibility Access",
                    description: "Required to paste transcribed text into your active app",
                    icon: "accessibility",
                    isGranted: permissionsService.accessibilityStatus,
                    isRequired: true,
                    onOpenSettings: {
                        permissionsService.requestAccessibilityPermission()
                    }
                )
            }
            .padding(.horizontal, AppSpacing.lg)

            Spacer()

            // Buttons
            VStack(spacing: AppSpacing.md) {
                PrimaryButton(
                    "Continue",
                    icon: "arrow.right",
                    isDisabled: !permissionsService.allRequiredPermissionsGranted
                ) {
                    isPresented = false
                }

                TextLinkButton(title: "Skip for now") {
                    isPresented = false
                }
            }
            .padding(.bottom, AppSpacing.xxl)
        }
        .padding(.horizontal, AppSpacing.xl)
        .frame(width: 450, height: 500)
        .background(AppColors.background)
        .onAppear {
            permissionsService.refreshStatus()
        }
    }
}

struct PermissionCard: View {
    let title: String
    let description: String
    let icon: String
    let isGranted: Bool
    let isRequired: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isGranted ? AppColors.success : AppColors.accent)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill((isGranted ? AppColors.success : AppColors.accent).opacity(0.15))
                )

            // Text
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    if isRequired {
                        Text("Required")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(AppColors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(AppColors.accent.opacity(0.15))
                            )
                    }
                }

                Text(description)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            // Status / Action
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.success)
            } else {
                Button(action: onOpenSettings) {
                    Text("Grant")
                        .font(AppTypography.captionMedium)
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(
                            Capsule()
                                .stroke(AppColors.accent, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(AppColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(AppColors.surfaceBorder, lineWidth: 1)
                )
        )
    }
}
