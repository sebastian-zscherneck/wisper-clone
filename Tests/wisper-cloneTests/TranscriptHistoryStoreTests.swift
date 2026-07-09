import Foundation
import Testing
@testable import wisper_clone

private func makeTemporaryHistoryFileURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wisper-clone-history-test-\(UUID().uuidString)")
        .appendingPathExtension("json")
}

@Test func historyStore_roundTripsEntries() throws {
    let url = makeTemporaryHistoryFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = FileTranscriptHistoryStore(fileURL: url)
    let entries = [
        TranscriptEntry(text: "second", createdAt: Date(timeIntervalSince1970: 1_700_000_060)),
        TranscriptEntry(text: "first", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    ]

    store.saveEntries(entries)
    let loaded = store.loadEntries()

    #expect(loaded == entries)
}

@Test func historyStore_returnsEmptyForCorruptFile() throws {
    let url = makeTemporaryHistoryFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not valid json".utf8).write(to: url)
    let store = FileTranscriptHistoryStore(fileURL: url)

    #expect(store.loadEntries() == [])
}

@Test func historyStore_returnsEmptyWhenFileMissing() {
    let url = makeTemporaryHistoryFileURL()
    let store = FileTranscriptHistoryStore(fileURL: url)

    #expect(store.loadEntries() == [])
}

@Test func historyStore_capsToMaxEntries() throws {
    let url = makeTemporaryHistoryFileURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let store = FileTranscriptHistoryStore(fileURL: url)
    let entries = (0..<150).map {
        TranscriptEntry(text: "entry \($0)", createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double($0)))
    }

    store.saveEntries(entries)
    let loaded = store.loadEntries()

    #expect(loaded.count == FileTranscriptHistoryStore.maxEntries)
    #expect(loaded == Array(entries.prefix(FileTranscriptHistoryStore.maxEntries)))
}
