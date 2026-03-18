import SwiftUI

@main
struct SuperWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app — no main window.
        // Settings window is fully managed by AppDelegate via the status bar menu.
        Settings {
            EmptyView()
        }
    }
}
