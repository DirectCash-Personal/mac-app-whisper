import SwiftUI
import AppKit
import AVFoundation

/// History tab — lists pending transcriptions, past transcriptions, and audio storage controls.
struct HistoryView: View {
    @EnvironmentObject var historyService: TranscriptionHistoryService
    @EnvironmentObject var pendingService: PendingTranscriptionService
    @EnvironmentObject var audioPersistence: AudioPersistenceService
    @State private var copiedId: UUID?
    @State private var searchText: String = ""
    @StateObject private var audioPlayer = AudioPlayerManager()

    // H12: Unified alert state to prevent binding conflicts
    enum ActiveAlert: Identifiable {
        case clearHistory, clearAudio
        var id: Int { hashValue }
    }
    @State private var activeAlert: ActiveAlert?

    private var filteredEntries: [TranscriptionEntry] {
        if searchText.isEmpty {
            return historyService.entries
        }
        return historyService.entries.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Transcription History")
                    .font(AppTypography.title)
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if !historyService.entries.isEmpty {
                    Button(action: { activeAlert = .clearHistory }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("Clear All")
                                .font(AppTypography.caption)
                        }
                        .foregroundColor(AppColors.error.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.xl)
            .padding(.bottom, AppSpacing.md)

            // Search
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textTertiary)
                    .font(.system(size: 13))

                TextField("Search transcriptions…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textPrimary)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(AppColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.surfaceBorder, lineWidth: 1)
                    )
            )
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.md)

            // Content
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: AppSpacing.sm) {
                    // Pending Transcriptions Section
                    if !pendingService.entries.isEmpty {
                        PendingTranscriptionsSection()
                            .padding(.bottom, AppSpacing.md)
                    }

                    // Audio Storage Section
                    AudioStorageSection(
                        audioPersistence: audioPersistence,
                        onClearAudio: { activeAlert = .clearAudio }
                    )
                    .padding(.bottom, AppSpacing.md)

                    // Transcription History
                    if filteredEntries.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredEntries) { entry in
                            TranscriptionEntryRow(
                                entry: entry,
                                isCopied: copiedId == entry.id,
                                audioDirectory: audioPersistence.audioDirectory,
                                onCopy: { copyText(entry) },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        audioPlayer.stop()
                                        historyService.removeEntry(entry)
                                    }
                                },
                                onRetranscribe: entry.audioFilename != nil ? { completion in
                                    retranscribeEntry(entry) { success, error in
                                        completion(success, error)
                                    }
                                } : nil,
                                audioPlayer: audioPlayer
                            )
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xl)
            }
        }
        // H12: Single unified alert to prevent binding conflicts
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .clearHistory:
                return Alert(
                    title: Text("Clear History"),
                    message: Text("This will permanently delete all \(historyService.entries.count) entries."),
                    primaryButton: .destructive(Text("Clear All")) {
                        withAnimation { historyService.clearAll() }
                    },
                    secondaryButton: .cancel()
                )
            case .clearAudio:
                return Alert(
                    title: Text("Clear Saved Audio"),
                    message: Text("This will permanently delete all saved audio files (\(audioPersistence.formattedTotalSize())). Pending transcriptions will lose their audio."),
                    primaryButton: .destructive(Text("Delete All Audio")) {
                        audioPersistence.deleteAllAudio()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary.opacity(0.5))

            Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textSecondary)

            Text(searchText.isEmpty
                 ? "Your transcription history will appear here."
                 : "Try a different search term.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }

    private func retranscribeEntry(_ entry: TranscriptionEntry, completion: @escaping (Bool, String?) -> Void) {
        guard let appDelegate = AppDelegate.shared else {
            completion(false, "App delegate not available")
            return
        }
        appDelegate.retranscribeHistoryEntry(entry: entry, completion: completion)
    }

    private func copyText(_ entry: TranscriptionEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedId = entry.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { copiedId = nil }
        }
    }
}

// MARK: - Pending Transcriptions Section

struct PendingTranscriptionsSection: View {
    @EnvironmentObject var pendingService: PendingTranscriptionService
    @EnvironmentObject var audioPersistence: AudioPersistenceService

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Section header
            HStack {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.error)

                    Text("Pending Transcriptions")
                        .font(AppTypography.bodyMedium)
                        .foregroundColor(AppColors.textPrimary)

                    Text("(\(pendingService.entries.count))")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                if pendingService.entries.count > 1 {
                    Button(action: {
                        retryAll()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("Retry All")
                                .font(AppTypography.caption)
                        }
                        .foregroundColor(AppColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(pendingService.entries) { entry in
                PendingEntryRow(entry: entry, onRetry: {
                    retryEntry(id: entry.id)
                }, onDelete: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        deletePendingWithAudio(entry)
                    }
                })
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(AppColors.error.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(AppColors.error.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func retryEntry(id: UUID) {
        // Find the AppDelegate to trigger retry
        if let appDelegate = AppDelegate.shared {
            appDelegate.retryPendingTranscription(id: id)
        }
    }

    private func retryAll() {
        if let appDelegate = AppDelegate.shared {
            appDelegate.retryAllPending()
        }
    }

    private func deletePendingWithAudio(_ entry: PendingTranscription) {
        let audioURL = audioPersistence.audioDirectory.appendingPathComponent(entry.audioFilename)
        audioPersistence.deleteAudio(at: audioURL)
        pendingService.removePending(id: entry.id)
    }
}

// MARK: - Pending Entry Row

struct PendingEntryRow: View {
    let entry: PendingTranscription
    let onRetry: () -> Void
    let onDelete: () -> Void

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }

    private var formattedDuration: String {
        let seconds = Int(entry.durationSeconds)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    statusIcon
                    Text(entry.audioFilename)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                }

                Text(entry.lastError)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.error.opacity(0.8))
                    .lineLimit(2)

                HStack(spacing: AppSpacing.md) {
                    Label(formattedDate, systemImage: "clock")
                    Label(formattedDuration, systemImage: "timer")
                    if entry.retryCount > 0 {
                        Label("\(entry.retryCount) retries", systemImage: "arrow.clockwise")
                    }
                }
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            VStack(spacing: AppSpacing.xs) {
                // Retry button
                Button(action: onRetry) {
                    Image(systemName: entry.status == .retrying ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .fill(AppColors.accent.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .disabled(entry.status == .retrying)
                .help("Retry transcription")

                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.error.opacity(0.7))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Delete pending transcription")
            }
        }
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(AppColors.surface.opacity(0.5))
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch entry.status {
        case .pending:
            Image(systemName: "clock.fill")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textTertiary)
        case .retrying:
            ProgressView()
                .controlSize(.mini)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(AppColors.error)
        }
    }
}

// MARK: - Audio Storage Section

struct AudioStorageSection: View {
    @ObservedObject var audioPersistence: AudioPersistenceService
    var onClearAudio: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textTertiary)

                Text("Saved Audio: \(audioPersistence.formattedTotalSize())")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            if audioPersistence.totalSize > 0 {
                Button(action: onClearAudio) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Clear Saved Audio")
                            .font(AppTypography.caption)
                    }
                    .foregroundColor(AppColors.error.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(AppColors.surface.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(AppColors.surfaceBorder.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Audio Player

// M10: Proper AVAudioPlayerDelegate for reliable playback completion
class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    @Published var playingEntryId: UUID?

    private var player: AVAudioPlayer?

    func togglePlayback(entryId: UUID, audioURL: URL) {
        if playingEntryId == entryId && isPlaying {
            stop()
            return
        }

        stop()

        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }

        do {
            player = try AVAudioPlayer(contentsOf: audioURL)
            player?.delegate = self
            player?.play()
            isPlaying = true
            playingEntryId = entryId
        } catch {
            print("Failed to play audio: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        playingEntryId = nil
    }

    // AVAudioPlayerDelegate — called when playback finishes naturally
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.stop()
        }
    }
}

// MARK: - Entry Row

struct TranscriptionEntryRow: View {
    let entry: TranscriptionEntry
    let isCopied: Bool
    let audioDirectory: URL?
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onRetranscribe: ((@escaping (Bool, String?) -> Void) -> Void)?
    @ObservedObject var audioPlayer: AudioPlayerManager
    @State private var isRetranscribing = false
    @State private var retranscribeError: String?

    @State private var isHovered: Bool = false

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: entry.timestamp)
    }

    private var formattedDuration: String {
        let seconds = Int(entry.durationSeconds)
        if seconds < 60 {
            return "\(seconds)s"
        }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    private var hasAudio: Bool {
        guard let filename = entry.audioFilename, let dir = audioDirectory else { return false }
        return FileManager.default.fileExists(atPath: dir.appendingPathComponent(filename).path)
    }

    private var isCurrentlyPlaying: Bool {
        audioPlayer.playingEntryId == entry.id && audioPlayer.isPlaying
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            // Play button (if audio exists)
            if hasAudio {
                Button(action: {
                    guard let filename = entry.audioFilename, let dir = audioDirectory else { return }
                    audioPlayer.togglePlayback(entryId: entry.id, audioURL: dir.appendingPathComponent(filename))
                }) {
                    Image(systemName: isCurrentlyPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(isCurrentlyPlaying ? AppColors.error : AppColors.accent)
                }
                .buttonStyle(.plain)
                .help(isCurrentlyPlaying ? "Stop" : "Play audio")
            }

            // Text content
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if entry.text.isEmpty {
                    // C4: Cancelled recording — not transcribed yet
                    Text("Not transcribed")
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textTertiary)
                        .italic()
                } else {
                    Text(entry.text)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: AppSpacing.md) {
                    Label(formattedDate, systemImage: "clock")
                    Label(entry.model, systemImage: "cpu")
                    Label(formattedDuration, systemImage: "timer")
                }
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            // Actions
            VStack(spacing: AppSpacing.xs) {
                // Copy button
                Button(action: onCopy) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isCopied ? AppColors.success : AppColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.sm)
                                .fill(isCopied ? AppColors.success.opacity(0.15) : AppColors.surface)
                        )
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                // Retranscribe button (if audio exists)
                if hasAudio, let onRetranscribe = onRetranscribe {
                    Button(action: {
                        isRetranscribing = true
                        retranscribeError = nil
                        onRetranscribe { success, errorMessage in
                            isRetranscribing = false
                            if !success {
                                retranscribeError = errorMessage ?? "Unknown error"
                            }
                        }
                    }) {
                        Image(systemName: isRetranscribing ? "hourglass" : "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(retranscribeError != nil ? AppColors.error : AppColors.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.sm)
                                    .fill(retranscribeError != nil ? AppColors.error.opacity(0.15) : AppColors.accent.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetranscribing)
                    .help(retranscribeError ?? "Re-transcribe audio")
                    .popover(isPresented: Binding(
                        get: { retranscribeError != nil },
                        set: { if !$0 { retranscribeError = nil } }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Retranscription failed")
                                .font(AppTypography.bodyMedium)
                                .foregroundColor(AppColors.error)
                            Text(retranscribeError ?? "")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(4)
                        }
                        .padding(AppSpacing.md)
                        .frame(maxWidth: 280)
                    }
                }

                // Delete button (visible on hover)
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.error.opacity(0.7))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from history")
                    .transition(.opacity)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(isHovered ? AppColors.surface : AppColors.surface.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .stroke(AppColors.surfaceBorder.opacity(isHovered ? 1 : 0.5), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
