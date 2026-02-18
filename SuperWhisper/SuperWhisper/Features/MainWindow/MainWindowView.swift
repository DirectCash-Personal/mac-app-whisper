import SwiftUI

/// Main window view — the entry point UI when the app is visible.
struct MainWindowView: View {
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var permissionsService: PermissionsService
    @State private var showPermissions = false

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom title bar
                HStack {
                    Spacer()

                    VStack(spacing: 2) {
                        HStack(spacing: AppSpacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.accentGradient)
                                    .frame(width: 28, height: 28)

                                Image(systemName: "waveform")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            Text("SuperWhisper")
                                .font(AppTypography.title2)
                                .foregroundColor(AppColors.textPrimary)
                        }

                        Text("Pro v1.0.0")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()
                }
                .padding(.vertical, AppSpacing.lg)
                .background(AppColors.background.opacity(0.8))

                Divider().opacity(0.1)

                // Settings content
                SettingsWindow()
                    .environmentObject(settingsService)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Check permissions on launch
            permissionsService.refreshStatus()
            if !permissionsService.allRequiredPermissionsGranted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showPermissions = true
                }
            }
        }
        .sheet(isPresented: $showPermissions) {
            PermissionsView(isPresented: $showPermissions)
                .environmentObject(permissionsService)
        }
    }
}
