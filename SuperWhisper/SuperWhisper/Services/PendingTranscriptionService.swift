import Foundation

/// Status of a pending transcription.
enum PendingStatus: String, Codable {
    case pending
    case retrying
    case failed
}

/// A transcription that failed and is waiting for retry.
struct PendingTranscription: Identifiable, Codable {
    let id: UUID
    let audioFilename: String  // filename only (relative to audio directory)
    let timestamp: Date
    let durationSeconds: TimeInterval
    let model: String
    let language: String
    var retryCount: Int
    var lastError: String
    var status: PendingStatus

    init(audioFilename: String, durationSeconds: TimeInterval, model: String, language: String, error: String) {
        self.id = UUID()
        self.audioFilename = audioFilename
        self.timestamp = Date()
        self.durationSeconds = durationSeconds
        self.model = model
        self.language = language
        self.retryCount = 0
        self.lastError = error
        self.status = .pending
    }
}

/// Persists failed transcriptions for manual retry.
class PendingTranscriptionService: ObservableObject {
    @Published var entries: [PendingTranscription] = []

    private let fileURL: URL

    init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not available")
        }
        let appDir = appSupport.appendingPathComponent("SuperWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("pending_transcriptions.json")
        load()
    }

    /// Add a failed transcription to the pending queue.
    func addPending(audioFilename: String, durationSeconds: TimeInterval, model: String, language: String, error: String) {
        let entry = PendingTranscription(
            audioFilename: audioFilename,
            durationSeconds: durationSeconds,
            model: model,
            language: language,
            error: error
        )
        entries.insert(entry, at: 0)
        save()
    }

    /// Remove a pending entry (after successful retry or manual delete).
    func removePending(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Update status of a pending entry.
    func updateStatus(id: UUID, status: PendingStatus, error: String? = nil) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = status
        if let error = error {
            entries[index].lastError = error
        }
        if status == .retrying {
            entries[index].retryCount += 1
        }
        save()
    }

    /// Clear all pending entries.
    func clearAll() {
        entries.removeAll()
        save()
    }

    var hasPending: Bool {
        !entries.isEmpty
    }

    var pendingCount: Int {
        entries.count
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save pending transcriptions: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            var loaded = try JSONDecoder().decode([PendingTranscription].self, from: data)
            // Reset any "retrying" entries back to "pending" on launch
            var needsSave = false
            for i in loaded.indices where loaded[i].status == .retrying {
                loaded[i].status = .pending
                needsSave = true
            }
            entries = loaded
            // H10: Only save if we actually modified entries (prevents corruption on decode failure)
            if needsSave { save() }
        } catch {
            // H2: Backup corrupted file and start fresh
            print("Failed to load pending transcriptions: \(error). Backing up corrupted file.")
            let backupURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent("pending_transcriptions_corrupted_\(Date().timeIntervalSince1970).json")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            entries = []
        }
    }
}
