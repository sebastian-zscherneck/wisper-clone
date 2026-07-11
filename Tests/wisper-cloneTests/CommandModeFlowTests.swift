import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func commandFlow_appliesInstructionToSelectionAndPastesResult() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command with selection")
    let pasteboard = SpyPasteboard()
    let chatClient = SpyChatClient(result: "Hi")
    let capturer = SpySelectedTextCapturer(result: "Hello world")
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "make it shorter"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient,
        selectedTextCapturer: capturer
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPasteCount(1, in: pasteboard)

    #expect(pasteboard.pastedTexts == ["Hi"])
    #expect(capturer.captureCount == 1)
    #expect(coordinator.lastTranscript == "Hi")

    let request = try #require(chatClient.requests.first)
    #expect(request.userMessage.contains("make it shorter"))
    #expect(request.userMessage.contains("Hello world"))
    #expect(request.model == OpenAIChatClient.commandModel)

    let entry = try #require(coordinator.history.first)
    #expect(entry.text == "Hi")
    #expect(entry.rawText == "Hello world")
    #expect(!FileManager.default.fileExists(atPath: audioURL.path))
}

@MainActor
@Test func commandFlow_withoutSelectionGeneratesTextAndMarksNoSelectionInPrompt() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command without selection")
    let pasteboard = SpyPasteboard()
    let chatClient = SpyChatClient(result: "Generated text")
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "write a greeting"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient,
        selectedTextCapturer: SpySelectedTextCapturer(result: nil)
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPasteCount(1, in: pasteboard)

    #expect(pasteboard.pastedTexts == ["Generated text"])

    let request = try #require(chatClient.requests.first)
    #expect(request.userMessage.contains("(No text selected.)"))
}

@MainActor
@Test func commandFlow_chatFailureFailsHardWithoutPasting() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command chat failure")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "make it shorter"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: SpyChatClient(error: DictationError.chatCompletionFailed("boom")),
        selectedTextCapturer: SpySelectedTextCapturer(result: "Hello world")
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.failed, in: coordinator)

    #expect(pasteboard.pastedTexts.isEmpty)
    #expect(pasteboard.copiedTexts.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: audioURL.path))
}

@MainActor
@Test func commandFlow_doubleTapDuringCommandRecordingDoesNotEnableHandsFree() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command double tap")
    let pasteboard = SpyPasteboard()
    let hotkeyManager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "make it shorter"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: SpyChatClient(result: "Hi"),
        hotkeyManager: hotkeyManager,
        selectedTextCapturer: SpySelectedTextCapturer(result: "Hello world")
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)

    // A stray double-tap of the dictation trigger during a command recording must not
    // flip on hands-free mode — that would let the next dictation press finish this
    // command recording prematurely.
    hotkeyManager.onDoubleTap?()
    #expect(!coordinator.isHandsFreeActive)

    coordinator.finishRecording()
    try await expectPasteCount(1, in: pasteboard)
    #expect(pasteboard.pastedTexts == ["Hi"])
}

@MainActor
@Test func commandFlow_dictationReleaseWhileCommandRecordingDoesNotFinishIt() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command dictation release")
    let pasteboard = SpyPasteboard()
    let hotkeyManager = HotkeyManager(hotkeys: [.fn])
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "make it shorter"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: SpyChatClient(result: "Hi"),
        hotkeyManager: hotkeyManager,
        selectedTextCapturer: SpySelectedTextCapturer(result: "Hello world")
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)

    // A stray dictation-trigger release while a command recording is in progress
    // must not finish it.
    hotkeyManager.onRelease?()
    #expect(coordinator.phase == DictationPhase.recording)
    #expect(pasteboard.pastedTexts.isEmpty)

    coordinator.finishRecording()
    try await expectPasteCount(1, in: pasteboard)
    #expect(pasteboard.pastedTexts == ["Hi"])
}

@MainActor
@Test func setCommandHotkey_rejectsSoleDictationHotkeyToAvoidDualRole() async throws {
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.preferences.hotkeys = [.fn]
    coordinator.setCommandHotkey(.fn)

    #expect(coordinator.preferences.commandHotkey == nil)
    #expect(coordinator.preferences.hotkeys == [.fn])
}

@MainActor
@Test func commandFlow_emptyInstructionFailsWithNoInstructionAndDoesNotPaste() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command empty instruction")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "   "),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: SpyChatClient(result: "should never be pasted"),
        selectedTextCapturer: SpySelectedTextCapturer(result: "Hello world")
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.failed, in: coordinator)

    #expect(coordinator.statusText == DictationError.noInstruction.errorDescription)
    #expect(pasteboard.pastedTexts.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: audioURL.path))
}

@MainActor
@Test func commandFlow_selectionOver1000WordsFailsWithoutChatRequest() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command long selection")
    let pasteboard = SpyPasteboard()
    let chatClient = SpyChatClient(result: "should never be sent")
    let longSelection = Array(repeating: "word", count: 1_001).joined(separator: " ")
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "make it shorter"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient,
        selectedTextCapturer: SpySelectedTextCapturer(result: longSelection)
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.failed, in: coordinator)

    #expect(coordinator.statusText == DictationError.selectionTooLong.errorDescription)
    #expect(chatClient.requests.isEmpty)
    #expect(pasteboard.pastedTexts.isEmpty)
}

@MainActor
@Test func commandFlow_voiceRuleAdditionSavesRuleWithoutChatRequestOrPaste() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command voice rule")
    let pasteboard = SpyPasteboard()
    let chatClient = SpyChatClient(result: "should never be sent")
    let notifier = SpyNotifier()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "Merke dir als Regel: nie Ausrufezeichen"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient,
        notifier: notifier,
        selectedTextCapturer: SpySelectedTextCapturer(result: nil)
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(coordinator.rules == ["nie Ausrufezeichen"])
    #expect(coordinator.statusText == "Regel gespeichert")
    #expect(chatClient.requests.isEmpty)
    #expect(pasteboard.pastedTexts.isEmpty)
    #expect(notifier.notifications.contains { $0.body == "nie Ausrufezeichen" })
}

@MainActor
@Test func commandFlow_normalInstructionIsUnaffectedByRuleTriggerCheck() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command normal instruction")
    let pasteboard = SpyPasteboard()
    let chatClient = SpyChatClient(result: "Hi")
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "make it shorter"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient,
        selectedTextCapturer: SpySelectedTextCapturer(result: "Hello world")
    )

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPasteCount(1, in: pasteboard)

    #expect(chatClient.requests.count == 1)
    #expect(coordinator.rules.isEmpty)
}

@MainActor
@Test func commandFlow_withoutSelectionIncludesLastTranscriptReferenceInUserMessage() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "dictation then command")
    let pasteboard = SpyPasteboard()
    let chatClient = SpyChatClient(result: "Generated text")
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SequencedTranscriptionClient(results: ["the meeting is at 3pm", "write a follow-up about that"]),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: chatClient,
        selectedTextCapturer: SpySelectedTextCapturer(result: nil)
    )

    // First, a plain dictation populates lastTranscript.
    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPasteCount(1, in: pasteboard)
    #expect(coordinator.lastTranscript == "the meeting is at 3pm")

    // Then a no-selection command should reference that last dictation.
    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPasteCount(2, in: pasteboard)

    let request = try #require(chatClient.requests.first)
    #expect(request.userMessage.contains("For reference, the user's most recent dictation"))
    #expect(request.userMessage.contains("the meeting is at 3pm"))
}

@MainActor
@Test func commandFlow_isCommandRecordingTrueWhileRecordingAndFalseAfterFinish() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "command recording flag")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "make it shorter"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: SpyChatClient(result: "Hi"),
        selectedTextCapturer: SpySelectedTextCapturer(result: "Hello world")
    )

    #expect(!coordinator.isCommandRecording)

    coordinator.beginCommandRecording()
    try await expectPhase(.recording, in: coordinator)
    #expect(coordinator.isCommandRecording)

    coordinator.finishRecording()
    try await expectPasteCount(1, in: pasteboard)
    #expect(!coordinator.isCommandRecording)
}

@MainActor
@Test func dictationFlow_isCommandRecordingStaysFalseForPlainDictation() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "plain dictation flag")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "hello"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    #expect(!coordinator.isCommandRecording)

    coordinator.finishRecording()
    try await expectPasteCount(1, in: pasteboard)
    #expect(!coordinator.isCommandRecording)
}
