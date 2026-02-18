import SwiftUI

/// Secure input field for API keys with show/hide toggle.
struct SecureInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: AppSpacing.sm) {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .foregroundColor(AppColors.textPrimary)

                Button(action: { isRevealed.toggle() }) {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.surfaceBorder, lineWidth: 1)
                    )
            )
        }
    }
}

/// Standard text input field.
struct StyledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .fill(AppColors.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md)
                                .stroke(AppColors.surfaceBorder, lineWidth: 1)
                        )
                )
        }
    }
}
