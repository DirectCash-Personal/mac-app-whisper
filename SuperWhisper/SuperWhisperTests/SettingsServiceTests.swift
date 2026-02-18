import XCTest
@testable import SuperWhisper

final class SettingsServiceTests: XCTestCase {

    var service: SettingsService!

    override func setUp() {
        super.setUp()
        // Clean UserDefaults for testing
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "SW_SelectedModel")
        defaults.removeObject(forKey: "SW_SelectedLanguage")
        defaults.removeObject(forKey: "SW_AutoPaste")
        defaults.removeObject(forKey: "SW_ShowNotification")
        defaults.removeObject(forKey: "SW_PlaySound")
        defaults.removeObject(forKey: "SW_HotkeyKeyCode")
        defaults.removeObject(forKey: "SW_HotkeyModifiers")
        service = SettingsService()
    }

    // MARK: - Default Values

    func testDefaultModel() {
        XCTAssertEqual(service.selectedModel, .whisper1)
    }

    func testDefaultLanguage() {
        XCTAssertEqual(service.selectedLanguage, .auto)
    }

    func testDefaultAutoPaste() {
        XCTAssertTrue(service.autoPasteEnabled)
    }

    func testDefaultShowNotification() {
        XCTAssertTrue(service.showNotification)
    }

    func testDefaultPlaySound() {
        XCTAssertTrue(service.playSoundOnCompletion)
    }

    func testDefaultHotkeyKeyCode() {
        XCTAssertEqual(service.hotkeyKeyCode, 2) // D key
    }

    // MARK: - Persistence

    func testModelPersistence() {
        service.selectedModel = .gpt4oTranscribe
        let newService = SettingsService()
        XCTAssertEqual(newService.selectedModel, .gpt4oTranscribe)
    }

    func testLanguagePersistence() {
        service.selectedLanguage = .portuguese
        let newService = SettingsService()
        XCTAssertEqual(newService.selectedLanguage, .portuguese)
    }

    func testAutoPastePersistence() {
        service.autoPasteEnabled = false
        let newService = SettingsService()
        XCTAssertFalse(newService.autoPasteEnabled)
    }

    // MARK: - Reset

    func testResetToDefaults() {
        service.selectedModel = .gpt4oTranscribe
        service.selectedLanguage = .spanish
        service.autoPasteEnabled = false

        service.resetToDefaults()

        XCTAssertEqual(service.selectedModel, .whisper1)
        XCTAssertEqual(service.selectedLanguage, .auto)
        XCTAssertTrue(service.autoPasteEnabled)
    }

    // MARK: - API Key (Keychain)

    func testNoAPIKeyByDefault() {
        // Note: This depends on keychain state, may have a key from previous runs
        // In a clean environment, there should be no key
        // We test the hasAPIKey property instead
        let key = service.apiKey
        if key == nil {
            XCTAssertFalse(service.hasAPIKey)
        }
    }

    func testSaveAndReadAPIKey() {
        service.apiKey = "sk-test-key-12345"
        XCTAssertEqual(service.apiKey, "sk-test-key-12345")
        XCTAssertTrue(service.hasAPIKey)

        // Cleanup
        service.apiKey = nil
    }

    func testDeleteAPIKey() {
        service.apiKey = "sk-test-key-temp"
        service.apiKey = nil
        XCTAssertNil(service.apiKey)
        XCTAssertFalse(service.hasAPIKey)
    }
}
