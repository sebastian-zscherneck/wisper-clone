import Foundation
import os

protocol TranscriptHistoryStoring {
    func loadEntries() -> [TranscriptEntry]
    func saveEntries(_ entries: [TranscriptEntry])
}

struct FileTranscriptHistoryStore: TranscriptHistoryStoring {
    static let maxEntries = 100

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.wisper-clone", category: "TranscriptHistoryStore")

    init(fileURL: URL = FileTranscriptHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("WisperClone", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    func loadEntries() -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([TranscriptEntry].self, from: data) else { return [] }
        return entries
    }

    func saveEntries(_ entries: [TranscriptEntry]) {
        let capped = Array(entries.prefix(Self.maxEntries))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(capped)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save transcript history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
