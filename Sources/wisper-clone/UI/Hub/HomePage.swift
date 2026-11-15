import SwiftUI

/// Start page: usage numbers, the last transcript and the dictation history by day.
struct HomePage: View {
    @ObservedObject var coordinator: DictationCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                statistics
                lastTranscript
                history
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Statistics

    private var statistics: some View {
        let summary = HistorySummary(entries: coordinator.history)
        return HStack(spacing: 12) {
            StatisticTile(value: "\(summary.wordsToday)", label: "words today", symbolName: "sun.max")
            StatisticTile(value: "\(summary.totalWords)", label: "words in history", symbolName: "text.alignleft")
            StatisticTile(value: "\(summary.dictations)", label: "dictations", symbolName: "waveform")
        }
    }

    // MARK: - Last transcript

    private var lastTranscript: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last Transcript")
                .font(.headline)
            Text(coordinator.lastTranscript.isEmpty ? "Hold your shortcut and speak. Your text shows up here." : coordinator.lastTranscript)
                .foregroundStyle(coordinator.lastTranscript.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            HStack {
                Button("Paste Again") {
                    coordinator.retryLastPaste()
                }
                Button("Copy") {
                    coordinator.copyLastTranscript()
                }
                if !coordinator.lastTranscript.isEmpty, let latestEntry = coordinator.history.first, latestEntry.wasEdited {
                    Button("Undo AI Edit") {
                        coordinator.pasteRaw(latestEntry)
                    }
                }
            }
            .disabled(coordinator.lastTranscript.isEmpty)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    coordinator.clearSessionHistory()
                }
                .buttonStyle(.borderless)
                .disabled(coordinator.history.isEmpty)
            }

            if coordinator.history.isEmpty {
                Text("No dictations yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(HistoryDay.group(coordinator.history)) { day in
                VStack(alignment: .leading, spacing: 0) {
                    Text(day.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                    VStack(spacing: 0) {
                        ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider()
                            }
                            HistoryRow(entry: entry, coordinator: coordinator)
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

private struct StatisticTile: View {
    let value: String
    let label: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HistoryRow: View {
    let entry: TranscriptEntry
    @ObservedObject var coordinator: DictationCoordinator
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(entry.createdAt, format: .dateTime.hour().minute())
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(entry.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button {
                    coordinator.copy(entry)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
                Button {
                    coordinator.removeHistoryEntry(entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove entry")
            }
            .buttonStyle(.borderless)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            if entry.wasEdited {
                Button("Copy Raw Transcript") {
                    coordinator.copyRaw(entry)
                }
            }
        }
    }
}
