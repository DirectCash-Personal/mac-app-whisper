import XCTest
@testable import SuperWhisper

final class TranscriptionServiceTests: XCTestCase {

    // MARK: - Model Properties

    func testWhisper1NotJsonOnly() {
        XCTAssertFalse(TranscriptionModel.whisper1.jsonResponseOnly)
    }

    func testGPT4oMiniJsonOnly() {
        XCTAssertTrue(TranscriptionModel.gpt4oMiniTranscribe.jsonResponseOnly)
    }

    func testGPT4oJsonOnly() {
        XCTAssertTrue(TranscriptionModel.gpt4oTranscribe.jsonResponseOnly)
    }

    // MARK: - Model Descriptions

    func testModelDescriptions() {
        XCTAssertEqual(TranscriptionModel.whisper1.description, "Whisper v1")
        XCTAssertEqual(TranscriptionModel.gpt4oMiniTranscribe.description, "GPT-4o Mini Transcribe")
        XCTAssertEqual(TranscriptionModel.gpt4oTranscribe.description, "GPT-4o Transcribe")
    }

    // MARK: - Language

    func testLanguageDescriptions() {
        XCTAssertEqual(TranscriptionLanguage.auto.description, "Auto-detect")
        XCTAssertEqual(TranscriptionLanguage.english.description, "English")
        XCTAssertEqual(TranscriptionLanguage.portuguese.description, "Portuguese")
    }

    func testAutoLanguageValueIsEmpty() {
        XCTAssertTrue(TranscriptionLanguage.auto.rawValue.isEmpty)
    }

    // MARK: - Error Descriptions

    func testNoAPIKeyError() {
        let error = TranscriptionError.noAPIKey
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("API key"))
    }

    func testInvalidAPIKeyError() {
        let error = TranscriptionError.invalidAPIKey
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Invalid"))
    }

    func testNetworkError() {
        let error = TranscriptionError.networkError("Connection lost")
        XCTAssertEqual(error.errorDescription, "Network error: Connection lost")
    }

    func testServerError() {
        let error = TranscriptionError.serverError(500, "Internal Server Error")
        XCTAssertTrue(error.errorDescription!.contains("500"))
    }

    // MARK: - Transcription Result

    func testTranscriptionResultDecoding() throws {
        let json = """
        {"text": "Hello world"}
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(TranscriptionResult.self, from: json)
        XCTAssertEqual(result.text, "Hello world")
    }

    // MARK: - No API Key Test

    func testTranscribeWithNoAPIKeyThrows() async {
        let settings = SettingsService()
        settings.apiKey = nil
        let service = TranscriptionService(settingsService: settings)

        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.wav")
            FileManager.default.createFile(atPath: tempURL.path, contents: Data())
            _ = try await service.transcribe(audioFileURL: tempURL)
            XCTFail("Should have thrown")
            try? FileManager.default.removeItem(at: tempURL)
        } catch let error as TranscriptionError {
            XCTAssertEqual(error.errorDescription, TranscriptionError.noAPIKey.errorDescription)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
