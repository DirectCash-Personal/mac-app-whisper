import AppKit
import ApplicationServices

/// Service for pasting transcribed text into the currently focused application.
class PasteService {

    /// Paste text into the active app by copying to pasteboard and simulating Cmd+V.
    func pasteText(_ text: String) {
        // Save current pasteboard content (optional, for restoring after)
        let pasteboard = NSPasteboard.general

        // Set text to pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()
        }
    }

    /// Check if Accessibility permission is granted (required for CGEvent paste simulation).
    var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }

    /// Request Accessibility permission with a prompt.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Private

    private func simulatePaste() {
        guard isAccessibilityGranted else {
            print("⚠️ Accessibility permission not granted. Cannot simulate paste.")
            requestAccessibilityPermission()
            return
        }

        // Create Cmd+V key events
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down: V (keycode 9) with Cmd modifier
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) else { return }
        keyDown.flags = .maskCommand

        // Key up
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        keyUp.flags = .maskCommand

        // Post events
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
