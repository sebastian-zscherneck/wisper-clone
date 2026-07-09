import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func dictationFlow_doubleTapLocksHandsFreeUntilNextPress() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "hands-free audio")
    let recorder = SpyRecorder(recordedFileURL: audioURL)
    let transcriber = SpyTranscriptionClient(result: "hands free result")
    let pasteboard = SpyPasteboard()
    let hotkeyManager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: transcriber,
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: hotkeyManager
    )

    hotkeyManager.onPress?()
    try await expectPhase(.recording, in: coordinator)

    hotkeyManager.onDoubleTap?()
    #expect(coordinator.isHandsFreeActive)

    // While hands-free is active, a release must not finish the recording.
    hotkeyManager.onRelease?()
    #expect(coordinator.phase == .recording)
    #expect(recorder.events == [.requestPermission, .start])

    // The next press ends the hands-free session and finishes the recording.
    hotkeyManager.onPress?()
    try await expectPhase(.idle, in: coordinator)

    #expect(!coordinator.isHandsFreeActive)
    #expect(recorder.events == [.requestPermission, .start, .stop])
    #expect(transcriber.requests.count == 1)
    #expect(pasteboard.pastedTexts == ["hands free result"])
}

@MainActor
@Test func dictationFlow_escapeCancelsRecordingWithoutTranscribing() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "escape audio")
    let recorder = SpyRecorder(recordedFileURL: audioURL)
    let transcriber = SpyTranscriptionClient(result: "unused")
    let pasteboard = SpyPasteboard()
    let hotkeyManager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: transcriber,
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: hotkeyManager
    )

    hotkeyManager.onPress?()
    try await expectPhase(.recording, in: coordinator)

    hotkeyManager.onEscape?()

    #expect(coordinator.phase == .idle)
    #expect(recorder.events == [.requestPermission, .start, .cancel])
    #expect(transcriber.requests.isEmpty)
    #expect(pasteboard.pastedTexts.isEmpty)
}

@MainActor
@Test func dictationFlow_escapeIsIgnoredWhenNotRecording() async throws {
    let recorder = SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a"))
    let hotkeyManager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: hotkeyManager
    )

    hotkeyManager.onEscape?()

    #expect(coordinator.phase == .idle)
    #expect(recorder.events.isEmpty)
}

@MainActor
@Test func dictationFlow_pasteLastShortcutRetriesLastTranscript() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "paste-last audio")
    let pasteboard = SpyPasteboard()
    let hotkeyManager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "paste me again"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: hotkeyManager
    )

    hotkeyManager.onPress?()
    try await expectPhase(.recording, in: coordinator)
    hotkeyManager.onRelease?()
    try await expectPhase(.idle, in: coordinator)

    #expect(pasteboard.pastedTexts == ["paste me again"])

    hotkeyManager.onPasteLastShortcut?()
    try await expectPasteCount(2, in: pasteboard)

    #expect(pasteboard.pastedTexts == ["paste me again", "paste me again"])
}
