import SwiftUI
import Carbon.HIToolbox

/// Keyboard shortcut recorder view for Settings.
/// Features: click to record, Escape to cancel, validates modifiers are present,
/// shows live modifier preview while recording, smooth animations.
struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @State private var isRecording = false
    @State private var isHovering = false
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var showSavedFeedback = false
    @State private var keyMonitor: Any?
    @State private var flagsMonitor: Any?

    var displayString: String {
        shortcutString(keyCode: keyCode, modifiers: modifiers)
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Main recorder button
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(isRecording ? AppColors.accent.opacity(0.08) : AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .stroke(
                                isRecording ? AppColors.accent :
                                    (isHovering ? AppColors.accent.opacity(0.4) : AppColors.surfaceBorder),
                                lineWidth: isRecording ? 2 : 1
                            )
                    )
                    .shadow(color: isRecording ? AppColors.accent.opacity(0.15) : .clear, radius: 12)

                if isRecording {
                    // Recording state
                    VStack(spacing: AppSpacing.sm) {
                        // Show live modifiers being held
                        if !liveModifiers.isEmpty {
                            Text(liveModifierString())
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .foregroundColor(AppColors.accent)
                                .transition(.scale.combined(with: .opacity))
                        }

                        // Pulsing dot + instruction
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 8, height: 8)
                                .scaleEffect(isRecording ? 1.2 : 0.8)
                                .animation(
                                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                    value: isRecording
                                )

                            Text(liveModifiers.isEmpty ? "Press shortcut or Fn key…" : "Now press a key")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                } else {
                    // Display current shortcut
                    VStack(spacing: AppSpacing.xs) {
                        Text(displayString)
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundColor(showSavedFeedback ? AppColors.success : AppColors.textPrimary)

                        if showSavedFeedback {
                            Text("Saved ✓")
                                .font(AppTypography.captionMedium)
                                .foregroundColor(AppColors.success)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .frame(width: 220, height: 90)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(AppAnimation.standard) {
                    isHovering = hovering
                }
            }
            .onTapGesture {
                if isRecording {
                    cancelRecording()
                } else {
                    startRecording()
                }
            }
            .animation(AppAnimation.standard, value: isRecording)
            .animation(AppAnimation.standard, value: liveModifiers.rawValue)

            // Helper text
            Text(isRecording ? "Esc to cancel" : "Click to change")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
                .animation(AppAnimation.standard, value: isRecording)
        }
    }

    // MARK: - Recording

    private func startRecording() {
        isRecording = true
        liveModifiers = []

        // Monitor flags changes (to show live modifier preview)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            self.liveModifiers = event.modifierFlags.intersection(relevant)
            return event
        }

        // Monitor key down (to capture the full shortcut)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == 53 {
                cancelRecording()
                return nil
            }

            let eventKeyCode = UInt32(event.keyCode)

            // Allow function keys (F1-F12) without modifiers
            let isFunctionKey = Self.functionKeyCodes.contains(eventKeyCode)

            let relevant: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            let pressedMods = event.modifierFlags.intersection(relevant)

            if pressedMods.isEmpty && !isFunctionKey {
                // Reject non-function keys without modifiers
                NSSound.beep()
                return nil
            }

            // Accept the shortcut
            self.keyCode = eventKeyCode
            self.modifiers = pressedMods.carbonFlags
            finishRecording()
            return nil
        }
    }

    private func finishRecording() {
        stopMonitors()
        isRecording = false
        liveModifiers = []

        // Show saved feedback
        withAnimation(AppAnimation.standard) {
            showSavedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(AppAnimation.standard) {
                showSavedFeedback = false
            }
        }
    }

    private func cancelRecording() {
        stopMonitors()
        isRecording = false
        liveModifiers = []
    }

    private func stopMonitors() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    // MARK: - Display Helpers

    private func liveModifierString() -> String {
        var parts: [String] = []
        if liveModifiers.contains(.control) { parts.append("⌃") }
        if liveModifiers.contains(.option) { parts.append("⌥") }
        if liveModifiers.contains(.shift) { parts.append("⇧") }
        if liveModifiers.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }

    private func shortcutString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

        let keyString = keyCodeToString(keyCode)
        parts.append(keyString)

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt32) -> String {
        let mapping: [UInt32: String] = [
            // Letters
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".",
            // Special
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            71: "⌧", 76: "⌅",
            // Arrow keys
            123: "←", 124: "→", 125: "↓", 126: "↑",
            // Function keys
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12",
        ]
        return mapping[keyCode] ?? "Key\(keyCode)"
    }

    /// Key codes for function keys F1-F12.
    static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111
    ]
}

// MARK: - Carbon Flags Extension

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}
