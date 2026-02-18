import SwiftUI

/// About tab — matched to Stitch "About SuperWhisper" screen.
struct AboutView: View {
    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // App Icon
            ZStack {
                Circle()
                    .fill(AppColors.accentGradient)
                    .frame(width: 80, height: 80)
                    .shadow(color: AppColors.accent.opacity(0.4), radius: 20)

                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }

            // App Name
            VStack(spacing: AppSpacing.xs) {
                Text("SuperWhisper")
                    .font(AppTypography.largeTitle)
                    .foregroundColor(AppColors.textPrimary)

                Text("Pro v1.0.0 (Build 1)")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textTertiary)
            }

            // Description
            Text("Voice-to-text dictation powered by OpenAI Whisper.\nSpeak naturally, paste instantly.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            // Links
            VStack(spacing: AppSpacing.md) {
                linkRow(icon: "globe", title: "Website", url: "https://superwhisper.app")
                linkRow(icon: "questionmark.circle", title: "Support", url: "https://superwhisper.app/support")
                linkRow(icon: "bird", title: "Twitter", url: "https://twitter.com/superwhisper")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()

            // Copyright
            Text("© 2025 SuperWhisper. All rights reserved.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
                .padding(.bottom, AppSpacing.lg)
        }
        .padding(AppSpacing.xxl)
    }

    private func linkRow(icon: String, title: String, url: String) -> some View {
        Button(action: {
            if let link = URL(string: url) {
                NSWorkspace.shared.open(link)
            }
        }) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 20)

                Text(title)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.surface)
            )
        }
        .buttonStyle(.plain)
    }
}
