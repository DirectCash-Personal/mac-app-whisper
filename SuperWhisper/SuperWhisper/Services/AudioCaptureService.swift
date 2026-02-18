import AVFoundation
import Foundation

/// Service for capturing microphone audio, computing waveform amplitudes, and recording to file.
class AudioCaptureService: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var startTime: Date?
    private var displayTimer: Timer?

    /// Callback for waveform amplitude updates (~30fps).
    var onAmplitudeUpdate: (([Float]) -> Void)?

    /// Callback for recording timer updates (every 0.1s).
    var onTimerUpdate: ((TimeInterval) -> Void)?

    @Published var isRecording = false

    // Amplitude history for waveform display
    private var amplitudeHistory: [Float] = Array(repeating: 0.15, count: 24)
    private let amplitudeHistorySize = 24

    func startRecording() throws {
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "superwhisper_\(Date().timeIntervalSince1970).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        self.recordingURL = fileURL

        // Create audio file for writing (use WAV for reliable recording)
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

        // Install tap for audio data
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Write to file
            try? self.audioFile?.write(from: buffer)

            // Compute RMS amplitude
            let amplitude = self.computeRMS(buffer: buffer)
            self.updateAmplitudeHistory(amplitude)
        }

        // Start engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
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
        displayTimer?.invalidate()
        displayTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false

        completion(recordingURL)
    }

    func cancelRecording() {
        displayTimer?.invalidate()
        displayTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isRecording = false

        // Delete temp file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    // MARK: - Private

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
        // Normalize to 0-1 range with some scaling for UI
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
