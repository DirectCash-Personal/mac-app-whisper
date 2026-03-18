import Foundation

/// A single transcription history entry.
struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let model: String
    let language: String
    let durationSeconds: TimeInterval
    let audioFilename: String?  // filename in audio directory (nil for old entries)

    init(text: String, model: String, language: String, durationSeconds: TimeInterval, audioFilename: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.model = model
        self.language = language
        self.durationSeconds = durationSeconds
        self.audioFilename = audioFilename
    }
}

/// Persists transcription history as JSON in Application Support.
class TranscriptionHistoryService: ObservableObject {
    @Published var entries: [TranscriptionEntry] = []

    private let fileURL: URL
    private var isLoaded = false  // #3: Guard against modification during load

    init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not available")
        }
        let appDir = appSupport.appendingPathComponent("SuperWhisper", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.fileURL = appDir.appendingPathComponent("transcription_history.json")
        load()
        isLoaded = true
    }

    /// Add a new transcription to history.
    func addEntry(text: String, model: String, language: String, durationSeconds: TimeInterval, audioFilename: String? = nil) {
        guard isLoaded else { return }  // #3: Don't modify until load completes
        let entry = TranscriptionEntry(
            text: text,
            model: model,
            language: language,
            durationSeconds: durationSeconds,
            audioFilename: audioFilename
        )
        entries.insert(entry, at: 0)  // Newest first

        // Cap at 200 entries
        if entries.count > 200 {
            entries = Array(entries.prefix(200))
        }

        save()
    }

    /// Remove a specific entry.
    func removeEntry(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Clear all history.
    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("❌ Failed to save history: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([TranscriptionEntry].self, from: data)
        } catch {
            // H2: Backup corrupted file and start fresh
            print("Failed to load history: \(error). Backing up corrupted file.")
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("transcription_history_corrupted_\(Date().timeIntervalSince1970).json")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            entries = []
        }
    }
}
