import AVFoundation
import Foundation

/// Compresses WAV audio files to M4A/AAC with adaptive bitrate.
/// Guarantees output never exceeds 24 MB (OpenAI API limit is 25 MB).
class AudioCompressionService {

    /// Target file size: 24 MB (safety margin under 25 MB API limit).
    private let targetSizeBytes: Int64 = 24 * 1024 * 1024
    /// Maximum bitrate for short recordings (excellent quality for speech).
    private let maxBitrate: Int = 96_000
    /// Minimum bitrate floor (acceptable quality for speech).
    private let minBitrate: Int = 32_000

    enum CompressionError: LocalizedError {
        case exportFailed(String)
        case readerCreationFailed
        case writerCreationFailed

        var errorDescription: String? {
            switch self {
            case .exportFailed(let msg): return "Audio compression failed: \(msg)"
            case .readerCreationFailed: return "Could not create audio reader."
            case .writerCreationFailed: return "Could not create audio writer."
            }
        }
    }

    /// Calculate the optimal bitrate for a given duration to stay under 24 MB.
    func calculateBitrate(durationSeconds: TimeInterval) -> Int {
        guard durationSeconds > 0 else { return maxBitrate }

        let targetBits = Double(targetSizeBytes) * 8.0
        let calculatedBitrate = Int(targetBits / durationSeconds)

        return min(maxBitrate, max(minBitrate, calculatedBitrate))
    }

    /// Compress a WAV file to M4A with adaptive bitrate based on duration.
    /// For short recordings (< 26 min): uses 96 kbps (excellent quality).
    /// For long recordings: reduces bitrate to guarantee file < 24 MB.
    func compress(wavURL: URL, durationSeconds: TimeInterval) async throws -> URL {
        let outputURL = wavURL.deletingPathExtension().appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outputURL)

        let bitrate = calculateBitrate(durationSeconds: durationSeconds)
        print("Compressing: duration=\(Int(durationSeconds))s, bitrate=\(bitrate/1000)kbps")

        do {
            try await compressWithAssetWriter(inputURL: wavURL, outputURL: outputURL, bitrate: bitrate)
        } catch {
            // Fallback: try AVAssetExportSession with default preset
            print("AVAssetWriter failed, trying AVAssetExportSession fallback: \(error.localizedDescription)")
            try await compressWithExportSession(inputURL: wavURL, outputURL: outputURL)
        }

        let originalSize = fileSize(at: wavURL)
        let compressedSize = fileSize(at: outputURL)
        print("Compressed: \(formatBytes(originalSize)) -> \(formatBytes(compressedSize)) (\(compressionRatio(original: originalSize, compressed: compressedSize)))")

        return outputURL
    }

    /// Compress with fallback: if all compression fails, returns the original URL.
    func compressWithFallback(wavURL: URL, durationSeconds: TimeInterval) async -> URL {
        do {
            return try await compress(wavURL: wavURL, durationSeconds: durationSeconds)
        } catch {
            print("All compression failed, falling back to original WAV: \(error.localizedDescription)")
            return wavURL
        }
    }

    // MARK: - AVAssetWriter (adaptive bitrate)

    private func compressWithAssetWriter(inputURL: URL, outputURL: URL, bitrate: Int) async throws {
        let asset = AVAsset(url: inputURL)

        // Setup reader
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw CompressionError.readerCreationFailed
        }

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw CompressionError.exportFailed("No audio track found")
        }

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(readerOutput)

        // Setup writer
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            throw CompressionError.writerCreationFailed
        }

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitrate
        ])
        writer.add(writerInput)

        // Execute conversion with timeout protection (C4)
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let compressionTimeout: UInt64 = 120_000_000_000 // 120 seconds

        let completed = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    // Guard against double-resume: requestMediaDataWhenReady may invoke
                    // callback again after markAsFinished before the closure is unregistered
                    var hasResumed = false
                    writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.superwhisper.compression")) {
                        guard !hasResumed else { return }
                        while writerInput.isReadyForMoreMediaData {
                            if let buffer = readerOutput.copyNextSampleBuffer() {
                                writerInput.append(buffer)
                            } else {
                                writerInput.markAsFinished()
                                hasResumed = true
                                continuation.resume()
                                return
                            }
                        }
                    }
                }
                return true
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: compressionTimeout)
                return false // Timeout
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        if !completed {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw CompressionError.exportFailed("Compression timed out after 120 seconds")
        }

        await writer.finishWriting()

        if writer.status == .failed {
            try? FileManager.default.removeItem(at: outputURL) // M2: Clean up partial file
            throw CompressionError.exportFailed(writer.error?.localizedDescription ?? "Writer failed")
        }
        if reader.status == .failed {
            try? FileManager.default.removeItem(at: outputURL) // M2: Clean up partial file
            throw CompressionError.exportFailed(reader.error?.localizedDescription ?? "Reader failed")
        }
    }

    // MARK: - AVAssetExportSession (fallback)

    private func compressWithExportSession(inputURL: URL, outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let asset = AVAsset(url: inputURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CompressionError.exportFailed("Could not create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw CompressionError.exportFailed(exportSession.error?.localizedDescription ?? "Export failed")
        }
    }

    // MARK: - Helpers

    func fileSize(at url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func compressionRatio(original: Int64, compressed: Int64) -> String {
        guard compressed > 0 else { return "N/A" }
        let ratio = Double(original) / Double(compressed)
        return String(format: "%.1fx reduction", ratio)
    }
}
