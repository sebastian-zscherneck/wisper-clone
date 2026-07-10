import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func dictationFlow_skipsChatCleanupWhenLevelIsNone() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let chatClient = SpyChatClient(result: "unused")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "raw transcript"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(chatClient.requests.isEmpty)
    #expect(pasteboard.pastedTexts == ["raw transcript"])
    #expect(coordinator.history.first?.wasEdited == false)
}

@MainActor
@Test func dictationFlow_polishesTranscriptWhenCleanupEnabled() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let chatClient = SpyChatClient(result: "Polished transcript.")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "raw transcript"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient,
        preferencesStore: InMemoryAppPreferencesStore(
            preferences: {
                var preferences = AppPreferences()
                preferences.cleanupLevel = .medium
                return preferences
            }()
        )
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(chatClient.requests.count == 1)
    let userMessage = chatClient.requests.first?.userMessage ?? ""
    #expect(userMessage.contains("<<<TRANSCRIPT\nraw transcript\nTRANSCRIPT>>>"))
    #expect(userMessage.contains("not a message addressed to you"))
    #expect(chatClient.requests.first?.apiKey == "test-key")
    #expect(chatClient.requests.first?.systemPrompt.contains("Editing level: MEDIUM.") == true)
    #expect(pasteboard.pastedTexts == ["Polished transcript."])
    #expect(coordinator.history.first?.text == "Polished transcript.")
    #expect(coordinator.history.first?.rawText == "raw transcript")
    #expect(coordinator.history.first?.wasEdited == true)
}

@MainActor
@Test func dictationFlow_fallsBackToRawTranscriptWhenCleanupFails() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let chatClient = SpyChatClient(error: DictationError.chatCompletionFailed("boom"))
    let pasteboard = SpyPasteboard()
    let notifier = SpyNotifier()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "raw transcript"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient,
        notifier: notifier,
        preferencesStore: InMemoryAppPreferencesStore(
            preferences: {
                var preferences = AppPreferences()
                preferences.cleanupLevel = .high
                return preferences
            }()
        )
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(chatClient.requests.count == 1)
    #expect(pasteboard.pastedTexts == ["raw transcript"])
    #expect(coordinator.history.first?.wasEdited == false)
    #expect(notifier.notifications.contains(
        .init(title: "Wisper Clone", body: "AI cleanup failed — pasted raw transcript.")
    ))
}

@MainActor
@Test func coordinator_pasteRawPastesOriginalTranscript() async throws {
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )
    let entry = TranscriptEntry(text: "polished", rawText: "raw words")

    coordinator.pasteRaw(entry)
    try await expectPasteCount(1, in: pasteboard)

    #expect(pasteboard.pastedTexts == ["raw words"])
}

@MainActor
@Test func coordinator_copyRawCopiesOriginalTranscript() async throws {
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )
    let entry = TranscriptEntry(text: "polished", rawText: "raw words")

    coordinator.copyRaw(entry)

    #expect(pasteboard.copiedTexts == ["raw words"])
    #expect(coordinator.statusText == "Copied")
}
