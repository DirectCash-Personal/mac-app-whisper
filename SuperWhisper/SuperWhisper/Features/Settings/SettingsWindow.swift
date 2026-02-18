import SwiftUI

/// Main settings window with sidebar navigation — matches Stitch "General Settings" screen.
struct SettingsWindow: View {
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var historyService: TranscriptionHistoryService

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case history = "History"
        case shortcuts = "Shortcuts"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .history: return "clock.arrow.circlepath"
            case .shortcuts: return "keyboard"
            case .about: return "info.circle.fill"
            }
        }
    }

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(spacing: AppSpacing.xs) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SidebarItem(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
                Spacer()
            }
            .padding(AppSpacing.md)
            .frame(width: 160)
            .background(AppColors.background.opacity(0.5))

            // Content
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .history:
                    HistoryView()
                case .shortcuts:
                    ShortcutSettingsView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.background)
        }
        .frame(minWidth: 650, maxWidth: 700, minHeight: 550, maxHeight: 700)
        .environmentObject(settingsService)
    }
}

struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.textSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(AppTypography.bodyMedium)
                    .foregroundColor(isSelected ? AppColors.textPrimary : AppColors.textSecondary)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isSelected ? AppColors.accent.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
