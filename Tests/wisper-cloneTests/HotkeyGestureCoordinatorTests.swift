import CoreGraphics
import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func hotkeyManager_fnControlWithoutConfigurationDoesNotTriggerDictationOrCommand() {
    // Neither .fnControl, .fn, nor a command hotkey is configured — holding Fn+Control
    // must not start dictation via the fallthrough branch of update(trigger:pressed:).
    let manager = HotkeyManager(hotkeys: [])
    var pressCount = 0
    var commandPressCount = 0
    manager.onPress = { pressCount += 1 }
    manager.onCommandPress = { commandPressCount += 1 }

    let flags = CGEventFlags.maskSecondaryFn.union(.maskControl)
    manager.handle(
        typeRawValue: CGEventType.flagsChanged.rawValue,
        flagsRawValue: flags.rawValue,
        keyCode: 0,
        mouseButtonNumber: 0
    )

    #expect(pressCount == 0)
    #expect(commandPressCount == 0)
}

@MainActor
@Test func dictationFlow_finishRecordingResetsHandsFreeFlag() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "test audio")
    let recorder = SpyRecorder(recordedFileURL: audioURL)
    let transcriber = SpyTranscriptionClient(result: "test result")
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

    // Directly call finishRecording() (simulating popover Stop button)
    // should reset the hands-free flag, not leave it stuck true
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(!coordinator.isHandsFreeActive)
    #expect(pasteboard.pastedTexts == ["test result"])
}

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
@Test func dictationFlow_commandReleaseWhileDictationRecordingDoesNotFinishIt() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "test audio")
    let recorder = SpyRecorder(recordedFileURL: audioURL)
    let transcriber = SpyTranscriptionClient(result: "test result")
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

    // A stray command-hotkey release (e.g. Fn+Control tapped while Fn dictation is
    // already recording) must not end the in-progress dictation.
    hotkeyManager.onCommandRelease?()
    #expect(coordinator.phase == .recording)
    #expect(recorder.events == [.requestPermission, .start])

    hotkeyManager.onRelease?()
    try await expectPhase(.idle, in: coordinator)
    #expect(pasteboard.pastedTexts == ["test result"])
}

@MainActor
@Test func dictationFlow_retryLastPasteIsNoOpWhileRecordingOrTranscribing() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "busy-guard audio")
    let pasteboard = SpyPasteboard()
    let hotkeyManager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "first result"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        hotkeyManager: hotkeyManager
    )

    hotkeyManager.onPress?()
    try await expectPhase(.recording, in: coordinator)
    hotkeyManager.onRelease?()
    try await expectPhase(.idle, in: coordinator)
    #expect(pasteboard.pastedTexts == ["first result"])

    // Start a second recording/transcription cycle and try to retry the paste while
    // it is still in flight — this must be a no-op, otherwise the concurrent paste()
    // call would race the pasteboard save/restore of the in-flight cycle.
    hotkeyManager.onPress?()
    try await expectPhase(.recording, in: coordinator)

    coordinator.retryLastPaste()
    #expect(pasteboard.pastedTexts.count == 1)

    hotkeyManager.onRelease?()
    try await expectPhase(.transcribing, in: coordinator)

    coordinator.retryLastPaste()
    #expect(pasteboard.pastedTexts.count == 1)

    try await expectPasteCount(2, in: pasteboard)
    #expect(pasteboard.pastedTexts == ["first result", "first result"])
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
