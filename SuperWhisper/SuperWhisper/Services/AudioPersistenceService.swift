import Foundation

/// Manages persistent audio file storage in Application Support.
/// Audio files are always kept until the user explicitly clears them.
class AudioPersistenceService: ObservableObject {
    let audioDirectory: URL
    @Published var totalSize: Int64 = 0

    init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not available")
        }
        let appDir = appSupport.appendingPathComponent("SuperWhisper", isDirectory: true)
        self.audioDirectory = appDir.appendingPathComponent("audio", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        refreshTotalSize()
    }

    /// Ensure audio directory exists, recreating if needed.
    private func ensureDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: audioDirectory.path) {
            try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        }
    }

    /// Copy audio from temp directory to persistent storage. Returns the new URL.
    /// Appends UUID suffix if a file with the same name already exists.
    func saveAudio(from tempURL: URL) throws -> URL {
        // #2: Verify directory exists before every save (handles permission/disk issues)
        try ensureDirectoryExists()
        let basename = tempURL.deletingPathExtension().lastPathComponent
        let ext = tempURL.pathExtension
        var destURL = audioDirectory.appendingPathComponent(tempURL.lastPathComponent)

        // Avoid filename collision
        if FileManager.default.fileExists(atPath: destURL.path) {
            let uniqueName = "\(basename)_\(UUID().uuidString.prefix(8)).\(ext)"
            destURL = audioDirectory.appendingPathComponent(uniqueName)
        }

        try FileManager.default.copyItem(at: tempURL, to: destURL)
        refreshTotalSize()
        return destURL
    }

    /// Delete a specific audio file.
    func deleteAudio(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        refreshTotalSize()
    }

    /// Delete all saved audio files.
    func deleteAllAudio() {
        let files = listAudioFiles()
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        refreshTotalSize()
    }

    /// List all saved audio files sorted by modification date (newest first).
    func listAudioFiles() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { ["wav", "m4a", "mp3", "mp4"].contains($0.pathExtension.lowercased()) }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA > dateB
            }
    }

    /// Total size of all saved audio files in bytes.
    func totalAudioSize() -> Int64 {
        let files = listAudioFiles()
        var total: Int64 = 0
        for file in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    /// Human-readable total size string.
    func formattedTotalSize() -> String {
        let bytes = totalAudioSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// M3: Debounced refresh to prevent rapid background tasks
    private var refreshWorkItem: DispatchWorkItem?

    func refreshTotalSize() {
        refreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let size = self?.totalAudioSize() ?? 0
            DispatchQueue.main.async {
                self?.totalSize = size
            }
        }
        refreshWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
