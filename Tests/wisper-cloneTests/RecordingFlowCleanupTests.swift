import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func dictationFlow_removesTemporaryRecordingAfterSuccessfulPaste() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "success")
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "done"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(!FileManager.default.fileExists(atPath: audioURL.path))
}

@MainActor
@Test func dictationFlow_removesTemporaryRecordingWhenTranscriptionFails() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "transcription failure")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(error: DictationError.transcriptionFailed("Bad response")),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.failed, in: coordinator)

    #expect(!FileManager.default.fileExists(atPath: audioURL.path))
    #expect(pasteboard.pastedTexts.isEmpty)
}

@MainActor
@Test func dictationFlow_copiesTranscriptWhenAutomaticPasteFails() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "paste failure")
    let pasteboard = SpyPasteboard(pasteError: DictationError.accessibilityDenied)
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "fallback text"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.failed, in: coordinator)

    #expect(coordinator.lastTranscript == "fallback text")
    #expect(pasteboard.pastedTexts == ["fallback text"])
    #expect(pasteboard.copiedTexts == ["fallback text"])
    #expect(!FileManager.default.fileExists(atPath: audioURL.path))
}
