import AppKit
import SwiftUI
import Carbon.HIToolbox
import AVFoundation
import Sparkle

/// AppDelegate handles global hotkey registration, the floating overlay panel,
/// and the menu bar status item. The app runs as a menu bar app (no dock icon).
class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel?
    private var hotkeyService: HotkeyService?
    private var appState: AppStateManager?
    private var settingsService: SettingsService?
    private var audioService: AudioCaptureService?
    private var transcriptionService: TranscriptionService?
    private var pasteService: PasteService?
    private var historyService: TranscriptionHistoryService?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: NSWindowController?
    private let updateService = UpdateService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 SuperWhisper launching...")

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

        // Configure F5/dictation key if Force F5 toggle is enabled
        HotkeyService.configureDictationKey(enabled: settingsService.forceF5DictationKey)

        // Setup global hotkey(s)
        hotkeyService = HotkeyService(settingsService: settingsService)
        hotkeyService?.onHotkeyPressed = { [weak self] in
            print("🎹 Hotkey pressed!")
            self?.handleHotkeyPressed()
        }
        hotkeyService?.register()

        // Setup menu bar status item
        setupStatusBar()

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

        print("✅ SuperWhisper ready!")
    }

    // MARK: - Microphone Permission

    private func requestMicrophoneIfNeeded() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 Microphone status: \(status.rawValue)")

        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("🎤 Microphone permission: \(granted ? "granted" : "denied")")
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
        print("🎹 Hotkey settings changed, re-registering...")
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

    @objc private func startDictationFromMenu() {
        print("📋 Start Dictation menu clicked")
        handleHotkeyPressed()
    }

    @objc private func showSettings() {
        // If settings window already exists, bring it to front
        if let controller = settingsWindowController, let window = controller.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let settingsService = settingsService,
              let historyService = historyService else { return }

        let settingsView = SettingsWindow()
            .environmentObject(settingsService)
            .environmentObject(historyService)

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
        guard let appState = appState else {
            print("❌ appState is nil")
            return
        }

        print("🔄 Current state: \(appState.currentState)")

        switch appState.currentState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        default:
            print("⚠️ Ignoring hotkey in state: \(appState.currentState)")
            break
        }
    }

    private func startRecording() {
        guard let appState = appState, let audioService = audioService else {
            print("❌ appState or audioService is nil")
            return
        }

        // Check API key first
        guard let settingsService = settingsService, settingsService.hasAPIKey else {
            print("⚠️ No API key configured")
            appState.transition(to: .error("No API key configured. Please add your OpenAI API key in Settings."))
            overlayPanel?.showOverlay()
            return  // ErrorOverlayView handles auto-dismiss via .dismissOverlay
        }

        // Check mic permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎤 Mic status at start: \(micStatus.rawValue)")

        guard micStatus == .authorized else {
            print("⚠️ Microphone not authorized — requesting…")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        print("✅ Mic granted! Starting recording…")
                        self?.startRecording()  // Retry
                    } else {
                        print("❌ Mic denied")
                        appState.transition(to: .error("Microphone access denied. Enable in System Settings → Privacy."))
                        self?.overlayPanel?.showOverlay()
                    }
                }
            }
            return
        }

        print("▶️ Starting recording…")
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

        do {
            try audioService.startRecording()
            print("🔴 Recording started!")
        } catch {
            print("❌ Recording failed: \(error)")
            appState.transition(to: .error(error.localizedDescription))
        }
    }

    private func stopRecording() {
        guard let appState = appState, let audioService = audioService else { return }

        print("⏹️ Stopping recording…")
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

    private func transcribeAudio(fileURL: URL) {
        guard let appState = appState, let transcriptionService = transcriptionService else { return }

        Task {
            do {
                let text = try await transcriptionService.transcribe(audioFileURL: fileURL)
                await MainActor.run {
                    appState.transcribedText = text

                    // Save to history (skip empty transcriptions)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let model = self.settingsService?.selectedModel.rawValue ?? "unknown"
                        let language = self.settingsService?.selectedLanguage.rawValue ?? "auto"
                        let duration = appState.recordingDuration
                        self.historyService?.addEntry(
                            text: trimmed,
                            model: model,
                            language: language,
                            durationSeconds: duration
                        )
                    }

                    self.pasteText(text)
                }
            } catch {
                await MainActor.run {
                    appState.transition(to: .error(error.localizedDescription))
                }
            }

            // Cleanup temp file
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func pasteText(_ text: String) {
        guard let appState = appState,
              let pasteService = pasteService,
              let settingsService = settingsService else { return }

        if settingsService.autoPasteEnabled {
            overlayPanel?.hideOverlay()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteService.pasteText(text)
                appState.transition(to: .success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.overlayPanel?.showOverlay()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.overlayPanel?.hideOverlay()
                        appState.transition(to: .idle)
                    }
                }
            }
        } else {
            appState.transition(to: .success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.overlayPanel?.hideOverlay()
                appState.transition(to: .idle)
            }
        }
    }

    func cancelRecording() {
        audioService?.cancelRecording()
        appState?.transition(to: .idle)
        overlayPanel?.hideOverlay()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
