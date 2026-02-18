import SwiftUI

@main
struct SuperWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppStateManager()
    @StateObject private var settingsService = SettingsService()
    @StateObject private var permissionsService = PermissionsService()
    @StateObject private var historyService = TranscriptionHistoryService()

    var body: some Scene {
        // Menu bar app — no main window by default.
        // Settings window is managed by AppDelegate via the status bar menu.
        Settings {
            SettingsWindow()
                .environmentObject(settingsService)
                .environmentObject(historyService)
        }
    }
}
