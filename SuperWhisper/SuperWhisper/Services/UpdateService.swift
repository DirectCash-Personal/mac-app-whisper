import Foundation
import Sparkle

/// Service that wraps Sparkle's SPUStandardUpdaterController for auto-update functionality.
/// Provides a clean interface for the rest of the app to interact with the update system.
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    /// The Sparkle updater controller — manages the entire update lifecycle
    private var updaterController: SPUStandardUpdaterController!

    /// Asked before a silent install: true when no recording or transcription is running.
    var isSafeToInstallUpdate: () -> Bool = { true }
    /// Sparkle's "install now and relaunch" block for an update already downloaded in the background.
    private var pendingImmediateInstallation: (() -> Void)?
    /// Retry interval while the user is mid-dictation; only runs while an update is waiting.
    private let busyRetrySeconds: Double = 60

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
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Observe the canCheckForUpdates property from Sparkle's updater
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    // MARK: - Silent install

    /// A menu bar app almost never quits, so "install on quit" would wait for days and Sparkle would end up
    /// showing a reminder window. Install right away instead, as soon as no dictation is in progress.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        pendingImmediateInstallation = immediateInstallHandler
        installPendingUpdateWhenIdle()
        return true
    }

    private func installPendingUpdateWhenIdle() {
        guard let immediateInstallation = pendingImmediateInstallation else { return }
        guard isSafeToInstallUpdate() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + busyRetrySeconds) { [weak self] in
                self?.installPendingUpdateWhenIdle()
            }
            return
        }
        pendingImmediateInstallation = nil
        print("🔄 Installing downloaded update and relaunching")
        immediateInstallation()
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
