import AVFoundation
import AppKit

/// Service for checking and managing system permissions (Microphone, Accessibility, Input Monitoring).
class PermissionsService: ObservableObject {
    @Published var microphoneStatus: Bool = false
    @Published var accessibilityStatus: Bool = false

    init() {
        refreshStatus()
    }

    /// Refresh all permission statuses.
    func refreshStatus() {
        microphoneStatus = checkMicrophonePermission()
        accessibilityStatus = checkAccessibilityPermission()
    }

    // MARK: - Microphone

    var isMicrophoneGranted: Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.microphoneStatus = granted
                completion(granted)
            }
        }
    }

    private func checkMicrophonePermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Accessibility

    var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Refresh after a delay (user might grant it)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshStatus()
        }
    }

    private func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    // MARK: - Open System Settings

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - All Required Permissions

    var allRequiredPermissionsGranted: Bool {
        return microphoneStatus && accessibilityStatus
    }

    var permissionItems: [PermissionStatus] {
        return [
            PermissionStatus(
                isGranted: microphoneStatus,
                title: "Microphone Access",
                description: "Required to capture your voice for transcription",
                isRequired: true
            ),
            PermissionStatus(
                isGranted: accessibilityStatus,
                title: "Accessibility Access",
                description: "Required to paste transcribed text into your active app",
                isRequired: true
            )
        ]
    }
}
