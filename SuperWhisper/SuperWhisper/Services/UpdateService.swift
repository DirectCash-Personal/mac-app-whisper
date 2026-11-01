import Foundation
import Sparkle

/// Service that wraps Sparkle's SPUStandardUpdaterController for auto-update functionality.
/// Provides a clean interface for the rest of the app to interact with the update system.
final class UpdateService: NSObject, ObservableObject {
    /// The Sparkle updater controller — manages the entire update lifecycle
    private let updaterController: SPUStandardUpdaterController

    /// Whether the updater can currently check for updates (observable for UI binding)
    @Published var canCheckForUpdates = false

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Whether updates are downloaded in the background and installed silently when the app quits
    /// (Mac restart, logout or Quit). Default on via SUAutomaticallyUpdate in Info.plist.
    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set { updaterController.updater.automaticallyDownloadsUpdates = newValue }
    }

    override init() {
        // Initialize with startingUpdater: false so we can start it manually
        // after the app finishes launching
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()

        // Observe the canCheckForUpdates property from Sparkle's updater
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Start the updater — call this once during applicationDidFinishLaunching
    func startUpdater() {
        updaterController.startUpdater()
        print("🔄 Sparkle updater started")
    }

    /// Trigger a manual check for updates (user-initiated)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// The current app version string from the bundle
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// The current build number from the bundle
    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
