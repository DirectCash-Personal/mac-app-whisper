import AVFoundation
import Foundation

/// Service for capturing microphone audio, computing waveform amplitudes, and recording to file.
class AudioCaptureService: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startTime: Date?
    private var displayTimer: Timer?
    private var consecutiveWriteErrors: Int = 0
    private let maxWriteErrors = 10
    /// Protects audioFile and isRecording from concurrent access (main thread vs audio thread)
    private let audioLock = NSLock()

    /// Callback for waveform amplitude updates (~30fps).
    var onAmplitudeUpdate: (([Float]) -> Void)?

    /// Callback for recording timer updates (every 0.1s).
    var onTimerUpdate: ((TimeInterval) -> Void)?

    /// Callback when recording fails mid-session (mic disconnect, system interruption).
    var onRecordingError: ((String) -> Void)?

    @Published var isRecording = false

    // Amplitude history for waveform display
    private var amplitudeHistory: [Float] = Array(repeating: 0.15, count: 24)
    private let amplitudeHistorySize = 24

    init() {
        // C3: Observe audio engine configuration changes (mic disconnect, route change)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        cleanupResources()
    }

    func startRecording() throws {
        // Clean up any previous state first
        cleanupResources()

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create temp WAV file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent("superwhisper_\(Date().timeIntervalSince1970).wav")
        self.recordingURL = wavURL

        guard let audioFile = try? AVAudioFile(
            forWriting: wavURL,
            settings: recordingFormat.settings,
            commonFormat: recordingFormat.commonFormat,
            interleaved: recordingFormat.isInterleaved
        ) else {
            throw AudioError.recordingFailed("Could not create audio file")
        }
        self.audioFile = audioFile
        consecutiveWriteErrors = 0

        // Install tap for audio data
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Lock protects audioFile/isRecording from main thread cleanup race
            self.audioLock.lock()
            guard self.isRecording, let file = self.audioFile else {
                self.audioLock.unlock()
                return
            }

            // C2: Track write errors instead of silently swallowing
            do {
                try file.write(from: buffer)
                self.consecutiveWriteErrors = 0
            } catch {
                self.consecutiveWriteErrors += 1
            }
            let errorCount = self.consecutiveWriteErrors
            self.audioLock.unlock()

            if errorCount >= self.maxWriteErrors {
                DispatchQueue.main.async {
                    self.onRecordingError?("Audio recording failed — microphone may have disconnected.")
                }
            }

            // Compute RMS amplitude
            let amplitude = self.computeRMS(buffer: buffer)
            self.updateAmplitudeHistory(amplitude)
        }

        // Start engine — C1: clean up tap if start fails
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // C1: Remove tap and clean up before rethrowing
            inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            self.audioFile = nil
            throw AudioError.engineStartFailed(error.localizedDescription)
        }

        startTime = Date()
        isRecording = true

        // Start display timer
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            let duration = Date().timeIntervalSince(start)
            self.onTimerUpdate?(duration)
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        cleanupResources()
        completion(recordingURL)
    }

    /// Cancel recording. Returns the file URL so caller can save it before deleting.
    func cancelRecording() -> URL? {
        let url = recordingURL
        cleanupResources()
        recordingURL = nil
        return url
    }

    // MARK: - Private

    /// C3: Handle audio engine configuration change (mic disconnect, route change)
    @objc private func handleAudioEngineConfigChange(_ notification: Notification) {
        guard isRecording else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onRecordingError?("Audio input changed — recording may be affected.")
        }
    }

    /// Centralized resource cleanup — prevents leaks and double-cleanup issues
    private func cleanupResources() {
        displayTimer?.invalidate()
        displayTimer = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil

        // Lock ensures audio tap callback is not mid-write when we nil audioFile
        audioLock.lock()
        audioFile = nil
        isRecording = false
        audioLock.unlock()
    }

    private func computeRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        return min(rms * 5.0, 1.0)
    }

    private func updateAmplitudeHistory(_ amplitude: Float) {
        amplitudeHistory.removeFirst()
        amplitudeHistory.append(amplitude)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onAmplitudeUpdate?(self.amplitudeHistory)
        }
    }
}
