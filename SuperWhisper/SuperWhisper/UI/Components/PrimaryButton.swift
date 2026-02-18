import SwiftUI

/// Primary action button with purple gradient, matching Stitch design.
struct PrimaryButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(AppTypography.bodyMedium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm + 2)
            .background(
                Group {
                    if isDisabled {
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .fill(Color.gray.opacity(0.3))
                    } else {
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .fill(AppColors.accentGradient)
                    }
                }
            )
            .shadow(color: isDisabled ? .clear : AppColors.accent.opacity(0.3), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .animation(AppAnimation.standard, value: isLoading)
    }
}

/// Secondary button with outline style.
struct SecondaryButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(AppTypography.bodyMedium)
            }
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(AppColors.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Destructive / text-only button.
struct TextLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
                .underline()
        }
        .buttonStyle(.plain)
    }
}
