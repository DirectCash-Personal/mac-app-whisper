import SwiftUI
import Carbon

/// Shortcut settings tab — Force F5 toggle + optional custom shortcut.
struct ShortcutSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @State private var keyCode: UInt32 = 2        // D
    @State private var modifiers: UInt32 = 0
    @State private var forceF5: Bool = true
    @State private var customEnabled: Bool = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppSpacing.xl) {
                // ── Header ──────────────────────────────────
                VStack(spacing: AppSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accent.opacity(0.1))
                            .frame(width: 52, height: 52)

                        Image(systemName: "keyboard")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(AppColors.accent)
                    }

                    Text("Global Shortcuts")
                        .font(AppTypography.title)
                        .foregroundColor(AppColors.textPrimary)

                    Text("Configure how to start/stop dictation")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.top, AppSpacing.lg)

                // ── F5 Toggle Card ──────────────────────────
                toggleCard(
                    isOn: $forceF5,
                    title: "Force F5 (Dictation Key)",
                    subtitle: "Remaps the Mac dictation key to SuperWhisper",
                    icon: "globe.badge.chevron.backward"
                ) { newValue in
                    settingsService.forceF5DictationKey = newValue
                    reRegisterHotkey()
                }

                // ── Divider ─────────────────────────────────
                HStack(spacing: AppSpacing.sm) {
                    dividerLine()
                    Text("AND / OR")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textTertiary)
                    dividerLine()
                }

                // ── Custom Shortcut Card ────────────────────
                VStack(spacing: AppSpacing.md) {
                    // Toggle header
                    Toggle(isOn: $customEnabled) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "command")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.accent)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom Shortcut")
                                    .font(AppTypography.bodyMedium)
                                    .foregroundColor(AppColors.textPrimary)
                                Text("Set your own keyboard shortcut")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))
                    .onChange(of: customEnabled) { _, newValue in
                        settingsService.customShortcutEnabled = newValue
                        reRegisterHotkey()
                    }

                    // Shortcut recorder (only when enabled)
                    if customEnabled {
                        ShortcutRecorderView(
                            keyCode: $keyCode,
                            modifiers: $modifiers
                        )
                        .onChange(of: keyCode) { _, newValue in
                            settingsService.hotkeyKeyCode = newValue
                            reRegisterHotkey()
                        }
                        .onChange(of: modifiers) { _, newValue in
                            settingsService.hotkeyModifiers = newValue
                            reRegisterHotkey()
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(AppSpacing.lg)
                .background(AppColors.backgroundSecondary)
                .cornerRadius(AppRadius.md)
                .animation(.easeInOut(duration: 0.2), value: customEnabled)

                // ── Tips ────────────────────────────────────
                VStack(spacing: AppSpacing.xs) {
                    tipRow(icon: "hand.raised", text: "Use ⌘, ⌃, ⌥, ⇧ or F1-F12 keys")
                    tipRow(icon: "escape", text: "Press Esc to cancel recording")
                    tipRow(icon: "lock.shield", text: "Requires Accessibility permission")
                }

                // ── Reset ───────────────────────────────────
                SecondaryButton("Reset to Default", icon: "arrow.counterclockwise") {
                    resetToDefault()
                }

                Spacer(minLength: AppSpacing.md)
            }
            .padding(.horizontal, AppSpacing.xxl)
        }
        .onAppear {
            keyCode = settingsService.hotkeyKeyCode
            modifiers = settingsService.hotkeyModifiers
            forceF5 = settingsService.forceF5DictationKey
            customEnabled = settingsService.customShortcutEnabled
        }
    }

    // MARK: - Components

    private func toggleCard(
        isOn: Binding<Bool>,
        title: String,
        subtitle: String,
        icon: String,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppRadius.md)
        .onChange(of: isOn.wrappedValue) { _, newValue in
            onChange(newValue)
        }
    }

    private func dividerLine() -> some View {
        Rectangle()
            .fill(AppColors.surfaceBorder)
            .frame(height: 1)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textTertiary)
                .frame(width: 16)

            Text(text)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
        }
    }

    // MARK: - Actions

    private func resetToDefault() {
        keyCode = 2  // D
        modifiers = UInt32(controlKey)  // Control
        forceF5 = true
        customEnabled = true
        settingsService.hotkeyKeyCode = keyCode
        settingsService.hotkeyModifiers = modifiers
        settingsService.forceF5DictationKey = true
        settingsService.customShortcutEnabled = true
        reRegisterHotkey()
    }

    private func reRegisterHotkey() {
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("SW_HotkeyChanged")
}
