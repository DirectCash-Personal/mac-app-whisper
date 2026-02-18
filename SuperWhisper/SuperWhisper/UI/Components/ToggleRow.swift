import SwiftUI

/// Toggle row with label and description, matching Stitch design.
struct ToggleRow: View {
    let title: String
    let description: String?
    let icon: String?
    @Binding var isOn: Bool

    init(
        _ title: String,
        description: String? = nil,
        icon: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(AppColors.textPrimary)

                if let description = description {
                    Text(description)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(AppColors.accent)
                .labelsHidden()
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
