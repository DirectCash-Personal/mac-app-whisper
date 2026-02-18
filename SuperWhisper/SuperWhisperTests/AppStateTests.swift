import XCTest
@testable import SuperWhisper

final class AppStateTests: XCTestCase {

    var appState: AppStateManager!

    override func setUp() {
        super.setUp()
        appState = AppStateManager()
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        XCTAssertEqual(appState.currentState, .idle)
    }

    func testInitialAmplitudesAreEmpty() {
        XCTAssertTrue(appState.waveformAmplitudes.isEmpty)
    }

    func testInitialDurationIsZero() {
        XCTAssertEqual(appState.recordingDuration, 0)
    }

    // MARK: - Valid Transitions

    func testIdleToRecording() {
        appState.transition(to: .recording)
        XCTAssertEqual(appState.currentState, .recording)
    }

    func testRecordingToProcessing() {
        appState.transition(to: .recording)
        appState.transition(to: .processing)
        XCTAssertEqual(appState.currentState, .processing)
    }

    func testProcessingToSuccess() {
        appState.transition(to: .recording)
        appState.transition(to: .processing)
        appState.transition(to: .success)
        XCTAssertEqual(appState.currentState, .success)
    }

    func testSuccessToIdle() {
        appState.transition(to: .recording)
        appState.transition(to: .processing)
        appState.transition(to: .success)
        appState.transition(to: .idle)
        XCTAssertEqual(appState.currentState, .idle)
    }

    func testRecordingToIdleCancel() {
        appState.transition(to: .recording)
        appState.transition(to: .idle)
        XCTAssertEqual(appState.currentState, .idle)
    }

    func testProcessingToError() {
        appState.transition(to: .recording)
        appState.transition(to: .processing)
        appState.transition(to: .error("Network error"))
        XCTAssertEqual(appState.currentState, .error("Network error"))
    }

    func testErrorToIdle() {
        appState.transition(to: .recording)
        appState.transition(to: .processing)
        appState.transition(to: .error("Test"))
        appState.transition(to: .idle)
        XCTAssertEqual(appState.currentState, .idle)
    }

    func testIdleToPermissionsNeeded() {
        appState.transition(to: .permissionsNeeded)
        XCTAssertEqual(appState.currentState, .permissionsNeeded)
    }

    // MARK: - Invalid Transitions

    func testIdleToSuccessInvalid() {
        appState.transition(to: .success)
        XCTAssertEqual(appState.currentState, .idle, "Should remain idle on invalid transition")
    }

    func testIdleToProcessingInvalid() {
        appState.transition(to: .processing)
        XCTAssertEqual(appState.currentState, .idle, "Should remain idle on invalid transition")
    }

    func testRecordingToSuccessInvalid() {
        appState.transition(to: .recording)
        appState.transition(to: .success)
        XCTAssertEqual(appState.currentState, .recording, "Should remain recording on invalid transition")
    }

    // MARK: - State Resets

    func testTransitionToIdleResetsAmplitudes() {
        appState.transition(to: .recording)
        appState.waveformAmplitudes = [0.1, 0.2, 0.3]
        appState.transition(to: .idle)
        XCTAssertTrue(appState.waveformAmplitudes.isEmpty)
    }

    func testTransitionToIdleResetsDuration() {
        appState.transition(to: .recording)
        appState.recordingDuration = 5.0
        appState.transition(to: .idle)
        XCTAssertEqual(appState.recordingDuration, 0)
    }

    func testTransitionToRecordingResetsText() {
        appState.transcribedText = "previous text"
        appState.transition(to: .recording)
        XCTAssertTrue(appState.transcribedText.isEmpty)
    }

    func testTransitionToErrorSetsMessage() {
        appState.transition(to: .recording)
        appState.transition(to: .processing)
        appState.transition(to: .error("Custom error"))
        XCTAssertEqual(appState.errorMessage, "Custom error")
    }

    // MARK: - Computed Properties

    func testIsRecording() {
        appState.transition(to: .recording)
        XCTAssertTrue(appState.isRecording)
    }

    func testIsProcessing() {
        appState.transition(to: .recording)
        appState.transition(to: .processing)
        XCTAssertTrue(appState.isProcessing)
    }

    func testIsSuccess() {
        appState.transition(to: .recording)
        appState.transition(to: .processing)
        appState.transition(to: .success)
        XCTAssertTrue(appState.isSuccess)
    }
}
