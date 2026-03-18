import AppKit
import SwiftUI
import Carbon.HIToolbox
import AVFoundation
import Sparkle

/// AppDelegate handles global hotkey registration, the floating overlay panel,
/// and the menu bar status item. The app runs as a menu bar app (no dock icon).
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Shared instance for access from SwiftUI views (NSApp.delegate is wrapped by SwiftUI adapter)
    static private(set) var shared: AppDelegate?

    private var overlayPanel: OverlayPanel?
    private var hotkeyService: HotkeyService?
    private var appState: AppStateManager?
    private var settingsService: SettingsService?
    private var audioService: AudioCaptureService?
    private var transcriptionService: TranscriptionService?
    private var pasteService: PasteService?
    private var historyService: TranscriptionHistoryService?
    private var audioPersistence: AudioPersistenceService?
    private var audioCompression: AudioCompressionService?
    private var pendingService: PendingTranscriptionService?
    private var statusItem: NSStatusItem?
    private var pendingMenuItem: NSMenuItem?
    private var settingsWindowController: NSWindowController?
    private let updateService = UpdateService()
    private var transcriptionTask: Task<Void, Never>?  // C6: Cancellable task handle
    private var retranscribeTask: Task<Void, Never>?  // H1: Cancellable retranscribe task
    private var retryTask: Task<Void, Never>?  // Cancellable retry task handle
    private var isProcessingHotkey = false  // H3: Debounce flag

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        print("SuperWhisper launching...")

        // Create services
        let settingsService = SettingsService()
        self.settingsService = settingsService
        let appState = AppStateManager()
        self.appState = appState
        self.audioService = AudioCaptureService()
        self.transcriptionService = TranscriptionService(settingsService: settingsService)
        self.pasteService = PasteService()
        let historyService = TranscriptionHistoryService()
        self.historyService = historyService
        let audioPersistence = AudioPersistenceService()
        self.audioPersistence = audioPersistence
        self.audioCompression = AudioCompressionService()
        let pendingService = PendingTranscriptionService()
        self.pendingService = pendingService

        // #5: Clean up orphaned temp files from previous sessions
        cleanupOrphanedTempFiles()

        // Configure F5/dictation key if Force F5 toggle is enabled
        HotkeyService.configureDictationKey(enabled: settingsService.forceF5DictationKey)

        // Setup global hotkey(s)
        hotkeyService = HotkeyService(settingsService: settingsService)
        hotkeyService?.onHotkeyPressed = { [weak self] in
            self?.handleHotkeyPressed()
        }
        hotkeyService?.register()

        // Setup menu bar status item
        setupStatusBar()
        updatePendingBadge()

        // Create overlay panel (hidden initially)
        setupOverlayPanel(appState: appState, settingsService: settingsService)

        // Observe stop/cancel notifications from overlay buttons
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStopRecording),
            name: .stopRecording,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCancelRecording),
            name: .cancelRecording,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissOverlay),
            name: .dismissOverlay,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeyChanged),
            name: .hotkeyChanged,
            object: nil
        )

        // Pre-request microphone permission at launch
        requestMicrophoneIfNeeded()

        // Start Sparkle auto-updater
        updateService.startUpdater()

        print("SuperWhisper ready!")
    }

    // MARK: - Microphone Permission

    private func requestMicrophoneIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("Microphone permission: \(granted ? "granted" : "denied")")
            }
        }
    }

    // MARK: - Stop / Cancel from overlay buttons

    @objc private func handleStopRecording() {
        guard let appState = appState, appState.currentState == .recording else { return }
        stopRecording()
    }

    @objc private func handleCancelRecording() {
        cancelRecording()
    }

    @objc private func handleDismissOverlay() {
        overlayPanel?.hideOverlay()
        if appState?.currentState != .idle {
            appState?.transition(to: .idle)
        }
    }

    @objc private func handleHotkeyChanged() {
        let forceF5 = settingsService?.forceF5DictationKey ?? true
        HotkeyService.configureDictationKey(enabled: forceF5)
        hotkeyService?.register()
    }

    // MARK: - Status Bar (Menu Bar App)

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SuperWhisper")
        }

        let menu = NSMenu()

        let dictationItem = NSMenuItem(title: "Start Dictation", action: #selector(startDictationFromMenu), keyEquivalent: "d")
        dictationItem.target = self
        menu.addItem(dictationItem)

        menu.addItem(NSMenuItem.separator())

        // Pending transcriptions item (hidden when no pending)
        let pendingItem = NSMenuItem(title: "No pending transcriptions", action: #selector(showSettings), keyEquivalent: "")
        pendingItem.target = self
        pendingItem.isHidden = true
        self.pendingMenuItem = pendingItem
        menu.addItem(pendingItem)

        menu.addItem(NSMenuItem.separator())

        let historyItem = NSMenuItem(title: "History…", action: #selector(showHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SuperWhisper", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func updatePendingBadge() {
        guard let pendingService = pendingService else { return }
        let count = pendingService.pendingCount

        if count > 0 {
            pendingMenuItem?.title = "\(count) pending transcription\(count == 1 ? "" : "s")"
            pendingMenuItem?.isHidden = false
            // Add badge to status bar icon
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "waveform.badge.exclamationmark", accessibilityDescription: "SuperWhisper - pending transcriptions")
            }
        } else {
            pendingMenuItem?.isHidden = true
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SuperWhisper")
            }
        }
    }

    @objc private func startDictationFromMenu() {
        handleHotkeyPressed()
    }

    @objc private func showHistory() {
        openSettingsWindow(tab: .history)
    }

    @objc private func showSettings() {
        openSettingsWindow(tab: .general)
    }

    private func openSettingsWindow(tab: SettingsWindow.SettingsTab) {
        // If settings window already exists, bring it to front
        if let controller = settingsWindowController, let window = controller.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let settingsService = settingsService,
              let historyService = historyService,
              let pendingService = pendingService,
              let audioPersistence = audioPersistence else { return }

        let settingsView = SettingsWindow(initialTab: tab)
            .environmentObject(settingsService)
            .environmentObject(historyService)
            .environmentObject(pendingService)
            .environmentObject(audioPersistence)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperWhisper Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.minSize = NSSize(width: 600, height: 500)
        window.maxSize = NSSize(width: 800, height: 800)

        // H7: Set delegate to clean up controller when window closes
        window.delegate = self

        let controller = NSWindowController(window: window)
        self.settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        updateService.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Overlay Panel

    private func setupOverlayPanel(appState: AppStateManager, settingsService: SettingsService) {
        overlayPanel = OverlayPanel(appState: appState, settingsService: settingsService)
    }

    // MARK: - Hotkey Logic

    private func handleHotkeyPressed() {
        guard let appState = appState else { return }

        // H3: Debounce rapid hotkey presses
        guard !isProcessingHotkey else { return }
        isProcessingHotkey = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isProcessingHotkey = false
        }

        switch appState.currentState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        default:
            break
        }
    }

    private func startRecording() {
        guard let appState = appState, let audioService = audioService else { return }

        // Check API key first
        guard let settingsService = settingsService, settingsService.hasAPIKey else {
            appState.transition(to: .error("No API key configured. Please add your OpenAI API key in Settings."))
            overlayPanel?.showOverlay()
            return
        }

        // Check mic permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)

        guard micStatus == .authorized else {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRecording()
                    } else {
                        appState.transition(to: .error("Microphone access denied. Enable in System Settings → Privacy."))
                        self?.overlayPanel?.showOverlay()
                    }
                }
            }
            return
        }

        appState.transition(to: .recording)
        overlayPanel?.showOverlay()

        audioService.onAmplitudeUpdate = { [weak appState] amplitudes in
            DispatchQueue.main.async {
                appState?.waveformAmplitudes = amplitudes
            }
        }

        audioService.onTimerUpdate = { [weak appState] duration in
            DispatchQueue.main.async {
                appState?.recordingDuration = duration
            }
        }

        // C2/C3: Handle mid-recording errors (mic disconnect, system interruption)
        // Cancel (not stop) to avoid transcribing corrupt/partial audio
        audioService.onRecordingError = { [weak self] message in
            guard let self = self, let appState = self.appState else { return }
            self.cancelRecording()
            appState.transition(to: .error(message))
        }

        do {
            try audioService.startRecording()
        } catch {
            appState.transition(to: .error(error.localizedDescription))
        }
    }

    private func stopRecording() {
        guard let appState = appState, let audioService = audioService else { return }

        appState.transition(to: .processing)

        audioService.stopRecording { [weak self] fileURL in
            guard let self = self, let fileURL = fileURL else {
                DispatchQueue.main.async {
                    appState.transition(to: .error("Failed to save recording"))
                }
                return
            }

            self.transcribeAudio(fileURL: fileURL)
        }
    }

    // MARK: - Transcription Flow (with compression, persistence, retry)

    private func transcribeAudio(fileURL: URL) {
        guard let appState = appState,
              let transcriptionService = transcriptionService,
              let audioPersistence = audioPersistence,
              let audioCompression = audioCompression else {
            // Prevent app from being stuck in .processing forever
            appState?.transition(to: .error("Internal error: services not initialized"))
            return
        }

        let recordingDuration = appState.recordingDuration
        let model = settingsService?.selectedModel.rawValue ?? "unknown"
        let language = settingsService?.selectedLanguage.rawValue ?? "auto"

        // C6: Store task handle for cancellation support
        transcriptionTask = Task {
            // C1: Save original WAV to persistent storage FIRST (before compression)
            // This ensures audio is never lost even if task is cancelled mid-compression
            let backupURL: URL
            do {
                backupURL = try audioPersistence.saveAudio(from: fileURL)
            } catch {
                await MainActor.run {
                    appState.transition(to: .error("Failed to save audio: \(error.localizedDescription)"))
                }
                return
            }

            // Step 1: Compress the persisted WAV → M4A
            let compressedURL = await audioCompression.compressWithFallback(wavURL: backupURL, durationSeconds: recordingDuration)

            // Use compressed version if different from backup, otherwise keep backup
            let persistedURL: URL
            if compressedURL != backupURL {
                // Replace WAV backup with compressed M4A
                do {
                    persistedURL = try audioPersistence.saveAudio(from: compressedURL)
                    audioPersistence.deleteAudio(at: backupURL) // Remove WAV backup
                } catch {
                    persistedURL = backupURL // Keep WAV if M4A save fails
                }
                try? FileManager.default.removeItem(at: compressedURL) // Clean temp M4A
            } else {
                persistedURL = backupURL
            }

            // Step 2: Delete original temp file from /tmp (safe — we have persistent copy)
            guard !Task.isCancelled else { return }
            try? FileManager.default.removeItem(at: fileURL)

            // Step 4: Transcribe with automatic retry
            transcriptionService.onRetryAttempt = { [weak appState] attempt, max in
                DispatchQueue.main.async {
                    appState?.retryInfo = "Attempt \(attempt)/\(max)"
                }
            }

            do {
                let text = try await transcriptionService.transcribe(audioFileURL: persistedURL)

                // Step 5: Success — save to history, paste
                await MainActor.run {
                    appState.transcribedText = text
                    appState.retryInfo = nil

                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.historyService?.addEntry(
                            text: trimmed,
                            model: model,
                            language: language,
                            durationSeconds: recordingDuration,
                            audioFilename: persistedURL.lastPathComponent
                        )
                    }

                    self.pasteText(text)
                }
            } catch {
                // Step 6: All retries failed — save to pending queue
                await MainActor.run {
                    appState.retryInfo = nil
                    self.pendingService?.addPending(
                        audioFilename: persistedURL.lastPathComponent,
                        durationSeconds: recordingDuration,
                        model: model,
                        language: language,
                        error: error.localizedDescription
                    )
                    self.updatePendingBadge()
                    appState.transition(to: .error("Transcription failed. Audio saved — retry in Settings → History."))
                }
            }
        }
    }

    /// Re-transcribe a history entry that already has audio saved.
    func retranscribeHistoryEntry(entry: TranscriptionEntry, completion: @escaping (Bool, String?) -> Void) {
        guard let audioPersistence = audioPersistence,
              let transcriptionService = transcriptionService,
              let historyService = historyService,
              let audioCompression = audioCompression,
              let filename = entry.audioFilename else {
            completion(false, "Internal error: services not available")
            return
        }

        let audioURL = audioPersistence.audioDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            completion(false, "Audio file not found: \(filename)")
            return
        }

        transcriptionService.onRetryAttempt = nil
        let entryId = entry.id

        // H1: Store task for cancellation on app termination
        retranscribeTask = Task {
            // If WAV, compress to M4A first (API may reject 32-bit float WAV from AVAudioEngine)
            var fileToTranscribe = audioURL
            var tempFiles: [URL] = []

            if audioURL.pathExtension.lowercased() == "wav" {
                let tempDir = FileManager.default.temporaryDirectory
                let tempWAV = tempDir.appendingPathComponent("retranscribe_\(UUID().uuidString.prefix(8)).wav")
                do {
                    try FileManager.default.copyItem(at: audioURL, to: tempWAV)
                    tempFiles.append(tempWAV)
                    let compressed = await audioCompression.compressWithFallback(
                        wavURL: tempWAV,
                        durationSeconds: entry.durationSeconds
                    )
                    if compressed != tempWAV {
                        tempFiles.append(compressed)
                    }
                    fileToTranscribe = compressed
                } catch {
                    // If copy/compress fails, try sending the WAV directly
                    print("Compression failed for retranscription, using WAV: \(error.localizedDescription)")
                }
            }

            defer {
                // Clean up temp files
                for file in tempFiles {
                    try? FileManager.default.removeItem(at: file)
                }
            }

            do {
                let text = try await transcriptionService.transcribe(audioFileURL: fileToTranscribe)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled else {
                    await MainActor.run { completion(false, nil) }
                    return
                }

                await MainActor.run {
                    if !trimmed.isEmpty {
                        let model = self.settingsService?.selectedModel.rawValue ?? entry.model
                        let language = self.settingsService?.selectedLanguage.rawValue ?? entry.language
                        // H4: Only remove if entry still exists (prevents duplicate on race)
                        if historyService.entries.contains(where: { $0.id == entryId }) {
                            historyService.removeEntry(entry)
                        }
                        historyService.addEntry(
                            text: trimmed,
                            model: model,
                            language: language,
                            durationSeconds: entry.durationSeconds,
                            audioFilename: filename
                        )
                        completion(true, nil)
                    } else {
                        completion(false, "Transcription returned empty text")
                    }
                }
            } catch {
                let errorMessage = error.localizedDescription
                print("Re-transcription failed: \(errorMessage)")
                await MainActor.run { completion(false, errorMessage) }
            }
        }
    }

    /// Retry a pending transcription. Called from the UI.
    func retryPendingTranscription(id: UUID) {
        // Clear overlay retry callback since this is a background retry
        transcriptionService?.onRetryAttempt = nil

        retryTask = Task {
            await retryPendingTranscriptionAsync(id: id)
        }
    }

    /// Retry all pending transcriptions sequentially to avoid rate limiting.
    func retryAllPending() {
        guard let pendingService = pendingService else { return }
        let ids = pendingService.entries.map { $0.id }

        retryTask = Task {
            for id in ids {
                guard !Task.isCancelled else { break }
                await retryPendingTranscriptionAsync(id: id)
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s between retries
            }
        }
    }

    private func retryPendingTranscriptionAsync(id: UUID) async {
        guard let pendingService = pendingService,
              let audioPersistence = audioPersistence,
              let transcriptionService = transcriptionService,
              let entry = pendingService.entries.first(where: { $0.id == id }) else { return }

        let audioURL = audioPersistence.audioDirectory.appendingPathComponent(entry.audioFilename)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            await MainActor.run {
                pendingService.updateStatus(id: id, status: .failed, error: "Audio file not found")
            }
            return
        }

        // C3: Set retrying AFTER all guards pass, so status is never stuck
        await MainActor.run {
            pendingService.updateStatus(id: id, status: .retrying)
        }

        do {
            let text = try await transcriptionService.transcribe(audioFileURL: audioURL)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                if !trimmed.isEmpty {
                    // C2: Pass audioFilename so entry has play/retranscribe
                    self.historyService?.addEntry(
                        text: trimmed,
                        model: entry.model,
                        language: entry.language,
                        durationSeconds: entry.durationSeconds,
                        audioFilename: entry.audioFilename
                    )
                }
                pendingService.removePending(id: id)
                self.updatePendingBadge()
            }
        } catch {
            await MainActor.run {
                pendingService.updateStatus(id: id, status: .failed, error: error.localizedDescription)
            }
        }
    }

    // H4: Flattened paste flow with state guards at each step
    private func pasteText(_ text: String) {
        guard let appState = appState,
              let pasteService = pasteService,
              let settingsService = settingsService else { return }

        if settingsService.autoPasteEnabled {
            overlayPanel?.hideOverlay()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard appState.currentState == .processing else { return }
                pasteService.pasteText(text)
                appState.transition(to: .success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard appState.currentState == .success else { return }
                    self?.overlayPanel?.showOverlay()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        guard appState.currentState == .success else { return }
                        self?.overlayPanel?.hideOverlay()
                        appState.transition(to: .idle)
                    }
                }
            }
        } else {
            appState.transition(to: .success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard appState.currentState == .success else { return }
                self?.overlayPanel?.hideOverlay()
                appState.transition(to: .idle)
            }
        }
    }

    // C4: Cancel saves audio to history so user can recover if cancelled by accident
    func cancelRecording() {
        guard let audioService = audioService else { return }

        let fileURL = audioService.cancelRecording()
        let duration = appState?.recordingDuration ?? 0

        if let fileURL = fileURL, let audioPersistence = audioPersistence {
            // Save audio to persistent storage
            if let savedURL = try? audioPersistence.saveAudio(from: fileURL) {
                // Add to history as "not transcribed"
                let model = settingsService?.selectedModel.rawValue ?? "unknown"
                let language = settingsService?.selectedLanguage.rawValue ?? "auto"
                historyService?.addEntry(
                    text: "",
                    model: model,
                    language: language,
                    durationSeconds: duration,
                    audioFilename: savedURL.lastPathComponent
                )
            }
            // Delete temp file
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Show brief notification then hide
        appState?.transition(to: .error("Recording cancelled. Audio saved to History."))
        overlayPanel?.showOverlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.overlayPanel?.hideOverlay()
            self?.appState?.transition(to: .idle)
        }
    }

    // H7: Clean up settings window controller when window closes
    func windowWillClose(_ notification: Notification) {
        settingsWindowController = nil
    }

    // C5: Clean up on app termination
    func applicationWillTerminate(_ notification: Notification) {
        // Cancel any in-flight tasks
        transcriptionTask?.cancel()
        transcriptionTask = nil
        retranscribeTask?.cancel()
        retranscribeTask = nil
        retryTask?.cancel()
        retryTask = nil

        // Stop recording if active and save audio
        if appState?.currentState == .recording {
            if let fileURL = audioService?.cancelRecording() {
                try? audioPersistence?.saveAudio(from: fileURL)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }

        // Unregister hotkeys (M8)
        hotkeyService?.unregister()
    }

    // #5: Remove orphaned superwhisper temp files from /tmp on launch
    private func cleanupOrphanedTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        ) else { return }

        for file in contents where file.lastPathComponent.hasPrefix("superwhisper_") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
