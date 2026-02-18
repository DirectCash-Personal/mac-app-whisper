import SwiftUI

/// A glass-morphism card container matching Stitch's dark glass aesthetic.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat
    var padding: CGFloat
    @ViewBuilder var content: () -> Content

    init(
        cornerRadius: CGFloat = AppRadius.lg,
        padding: CGFloat = AppSpacing.lg,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(AppColors.surfaceBorder, lineWidth: 1)
                    )
            )
    }
}

/// A sidebar-style card for settings sections.
struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        icon: String,
        iconColor: Color = AppColors.accent,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                    .background(iconColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

                Text(title)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textPrimary)
            }

            content()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
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
