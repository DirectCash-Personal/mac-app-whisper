import SwiftUI
import AppKit

/// History tab — lists all past transcriptions with copy buttons.
struct HistoryView: View {
    @EnvironmentObject var historyService: TranscriptionHistoryService
    @State private var copiedId: UUID?
    @State private var searchText: String = ""
    @State private var showClearConfirmation: Bool = false

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
                    Button(action: { showClearConfirmation = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                            Text("Clear All")
                                .font(AppTypography.caption)
                        }
                        .foregroundColor(AppColors.error.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .alert("Clear History", isPresented: $showClearConfirmation) {
                        Button("Cancel", role: .cancel) {}
                        Button("Clear All", role: .destructive) {
                            withAnimation { historyService.clearAll() }
                        }
                    } message: {
                        Text("This will permanently delete all \(historyService.entries.count) entries.")
                    }
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
            if filteredEntries.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: AppSpacing.sm) {
                        ForEach(filteredEntries) { entry in
                            TranscriptionEntryRow(
                                entry: entry,
                                isCopied: copiedId == entry.id,
                                onCopy: { copyText(entry) },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        historyService.removeEntry(entry)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()

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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Entry Row

struct TranscriptionEntryRow: View {
    let entry: TranscriptionEntry
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

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

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            // Text content
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(entry.text)
                    .font(AppTypography.body)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

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
