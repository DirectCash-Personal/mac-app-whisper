import Foundation
import Carbon.HIToolbox
import ServiceManagement

/// Service handling UserDefaults settings and API key storage.
/// API key is stored in UserDefaults with Base64 encoding (no Keychain popups).
class SettingsService: ObservableObject {
    private let defaults = UserDefaults.standard
    // M5: Serial queue for API key operations to prevent race conditions
    private let apiKeyQueue = DispatchQueue(label: "com.superwhisper.apikey")

    // MARK: - Keys
    private enum Keys {
        static let model = "SW_SelectedModel"
        static let language = "SW_SelectedLanguage"
        static let autoPaste = "SW_AutoPaste"
        static let showNotification = "SW_ShowNotification"
        static let playSound = "SW_PlaySound"
        static let hotkeyKeyCode = "SW_HotkeyKeyCode"
        static let hotkeyModifiers = "SW_HotkeyModifiers"
        static let forceF5 = "SW_ForceF5DictationKey"
        static let customShortcutEnabled = "SW_CustomShortcutEnabled"
        static let launchAtLogin = "SW_LaunchAtLogin"
        static let apiKey = "SW_APIKey_Encoded"
        static let vocabularyTerms = "SW_VocabularyTerms"
        static let migratedToGptTranscribe = "SW_MigratedToGptTranscribe"
    }

    // MARK: - Published Properties

    @Published var selectedModel: TranscriptionModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: Keys.model) }
    }

    @Published var selectedLanguage: TranscriptionLanguage {
        didSet { defaults.set(selectedLanguage.rawValue, forKey: Keys.language) }
    }

    @Published var autoPasteEnabled: Bool {
        didSet { defaults.set(autoPasteEnabled, forKey: Keys.autoPaste) }
    }

    @Published var showNotification: Bool {
        didSet { defaults.set(showNotification, forKey: Keys.showNotification) }
    }

    @Published var playSoundOnCompletion: Bool {
        didSet { defaults.set(playSoundOnCompletion, forKey: Keys.playSound) }
    }

    @Published var forceF5DictationKey: Bool {
        didSet { defaults.set(forceF5DictationKey, forKey: Keys.forceF5) }
    }

    @Published var customShortcutEnabled: Bool {
        didSet { defaults.set(customShortcutEnabled, forKey: Keys.customShortcutEnabled) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLoginItem()
        }
    }

    /// Comma-separated terms sent as `keywords` (gpt-transcribe) or as the prompt hint (older models).
    @Published var vocabularyTerms: String {
        didSet { defaults.set(vocabularyTerms, forKey: Keys.vocabularyTerms) }
    }

    var vocabularyTermList: [String] { TranscriptionVocabulary.terms(from: vocabularyTerms) }

    var hotkeyKeyCode: UInt32 {
        get { UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode)) }
        set { defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode) }
    }

    var hotkeyModifiers: UInt32 {
        get { UInt32(defaults.integer(forKey: Keys.hotkeyModifiers)) }
        set { defaults.set(Int(newValue), forKey: Keys.hotkeyModifiers) }
    }

    // MARK: - Init

    init() {
        // Load from UserDefaults or set defaults
        // One-time move of the GPT-4o choice to gpt-transcribe (Jarvis Voz on mark2 since 19/10/2026: p50 493 ms
        // against 739 ms, empty text on silent audio instead of the echo of the hint); GPT-4o stays as its fallback.
        if !defaults.bool(forKey: Keys.migratedToGptTranscribe) {
            if defaults.string(forKey: Keys.model) == TranscriptionModel.gpt4oTranscribe.rawValue {
                defaults.set(TranscriptionModel.gptTranscribe.rawValue, forKey: Keys.model)
            }
            defaults.set(true, forKey: Keys.migratedToGptTranscribe)
        }
        let modelRaw = defaults.string(forKey: Keys.model) ?? TranscriptionModel.gptTranscribe.rawValue
        self.selectedModel = TranscriptionModel(rawValue: modelRaw) ?? .gptTranscribe

        self.vocabularyTerms = defaults.string(forKey: Keys.vocabularyTerms)
            ?? TranscriptionVocabulary.defaultOperatorTerms.joined(separator: ", ")

        let langRaw = defaults.string(forKey: Keys.language) ?? TranscriptionLanguage.auto.rawValue
        self.selectedLanguage = TranscriptionLanguage(rawValue: langRaw) ?? .auto

        // Defaults: auto-paste ON, notifications ON, sound ON
        if defaults.object(forKey: Keys.autoPaste) == nil {
            defaults.set(true, forKey: Keys.autoPaste)
        }
        self.autoPasteEnabled = defaults.bool(forKey: Keys.autoPaste)

        if defaults.object(forKey: Keys.showNotification) == nil {
            defaults.set(true, forKey: Keys.showNotification)
        }
        self.showNotification = defaults.bool(forKey: Keys.showNotification)

        if defaults.object(forKey: Keys.playSound) == nil {
            defaults.set(true, forKey: Keys.playSound)
        }
        self.playSoundOnCompletion = defaults.bool(forKey: Keys.playSound)

        // Default: Force F5 dictation key ON
        if defaults.object(forKey: Keys.forceF5) == nil {
            defaults.set(true, forKey: Keys.forceF5)
        }
        self.forceF5DictationKey = defaults.bool(forKey: Keys.forceF5)

        // Default: Custom shortcut enabled
        if defaults.object(forKey: Keys.customShortcutEnabled) == nil {
            defaults.set(true, forKey: Keys.customShortcutEnabled)
        }
        self.customShortcutEnabled = defaults.bool(forKey: Keys.customShortcutEnabled)

        // Default custom hotkey: Control+D (keyCode 2)
        if defaults.object(forKey: Keys.hotkeyKeyCode) == nil {
            defaults.set(2, forKey: Keys.hotkeyKeyCode)  // D
            defaults.set(Int(controlKey), forKey: Keys.hotkeyModifiers)  // Control
        }

        // Default: Launch at Login ON
        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            defaults.set(true, forKey: Keys.launchAtLogin)
        }
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        // Apply launch-at-login state on init
        updateLoginItem()
    }

    // MARK: - API Key (UserDefaults with Base64 encoding)

    var apiKey: String? {
        get { apiKeyQueue.sync { readAPIKey() } }
        set {
            apiKeyQueue.sync { saveAPIKey(newValue) }
            objectWillChange.send()
        }
    }

    var hasAPIKey: Bool {
        guard let key = apiKey else { return false }
        return !key.isEmpty
    }

    private func saveAPIKey(_ value: String?) {
        guard let value = value, !value.isEmpty else {
            defaults.removeObject(forKey: Keys.apiKey)
            return
        }
        // Base64 encode to avoid plain-text storage
        if let data = value.data(using: .utf8) {
            defaults.set(data.base64EncodedString(), forKey: Keys.apiKey)
        }
    }

    private func readAPIKey() -> String? {
        guard let encoded = defaults.string(forKey: Keys.apiKey),
              let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Reset

    func resetToDefaults() {
        selectedModel = .gptTranscribe
        selectedLanguage = .auto
        vocabularyTerms = TranscriptionVocabulary.defaultOperatorTerms.joined(separator: ", ")
        autoPasteEnabled = true
        showNotification = true
        playSoundOnCompletion = true
        hotkeyKeyCode = 2  // D
        hotkeyModifiers = UInt32(controlKey)  // Control
        forceF5DictationKey = true
        customShortcutEnabled = true
        launchAtLogin = true
    }

    // MARK: - Launch at Login (SMAppService)

    private func updateLoginItem() {
        // Under XCTest the "main app" is the xctest agent: registering it adds xctest as a real login item.
        guard NSClassFromString("XCTestCase") == nil else { return }
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                try service.register()
                print("✅ Launch at Login: registered")
            } else {
                try service.unregister()
                print("✅ Launch at Login: unregistered")
            }
        } catch {
            print("⚠️ Launch at Login error: \(error.localizedDescription)")
        }
    }
}
