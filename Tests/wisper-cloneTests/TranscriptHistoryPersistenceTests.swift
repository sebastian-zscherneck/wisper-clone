import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func dictationFlow_persistsHistoryEntryAfterSuccessfulTranscription() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "persisted")
    let historyStore = InMemoryTranscriptHistoryStore()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "  saved text  "),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        historyStore: historyStore
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(historyStore.loadEntries().map(\.text) == ["saved text"])
    #expect(historyStore.saveCount == 1)
    #expect(coordinator.history.first?.wasEdited == false)
    #expect(coordinator.history.first?.rawText == coordinator.history.first?.text)
}

@MainActor
@Test func coordinator_loadsHistoryFromStoreOnInit() {
    let existing = [TranscriptEntry(text: "previous session")]
    let historyStore = InMemoryTranscriptHistoryStore(entries: existing)
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        historyStore: historyStore
    )

    #expect(coordinator.history == existing)
}

@MainActor
@Test func removeHistoryEntry_removesAndPersists() {
    let first = TranscriptEntry(text: "first")
    let second = TranscriptEntry(text: "second")
    let historyStore = InMemoryTranscriptHistoryStore(entries: [first, second])
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        historyStore: historyStore
    )

    coordinator.removeHistoryEntry(first.id)

    #expect(coordinator.history == [second])
    #expect(historyStore.loadEntries() == [second])
}

@MainActor
@Test func clearSessionHistory_persistsEmptyList() {
    let historyStore = InMemoryTranscriptHistoryStore(entries: [TranscriptEntry(text: "old")])
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        historyStore: historyStore
    )

    coordinator.clearSessionHistory()

    #expect(coordinator.history.isEmpty)
    #expect(historyStore.loadEntries().isEmpty)
}
