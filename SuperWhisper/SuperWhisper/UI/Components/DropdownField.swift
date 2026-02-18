import SwiftUI

/// Styled dropdown/picker matching Stitch dark theme.
struct DropdownField<T: Hashable>: View where T: CustomStringConvertible {
    let label: String
    let options: [T]
    @Binding var selection: T

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.description)
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.surfaceBorder, lineWidth: 1)
                    )
            )
            .tint(AppColors.textPrimary)
        }
    }
}
