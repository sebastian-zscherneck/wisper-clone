import Foundation
import Testing
@testable import wisper_clone

// The frontmost app can't be controlled from the test host, so these tests drive the
// hotkey override — the one signature path that does not depend on which app is in
// front. Per-app matching itself is covered by SignatureAppenderTests.

@MainActor
@Test func dictationFlow_appendsSignatureWhenOverrideIsArmed() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "raw transcript"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    // Auto-append is off by default, so the toggle arms the signature for one dictation.
    coordinator.toggleSignatureOverride()
    #expect(coordinator.signatureOverride == true)

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(pasteboard.pastedTexts == ["raw transcript\nMade with WisprFlow"])
    #expect(coordinator.history.first?.text == "raw transcript\nMade with WisprFlow")
    #expect(coordinator.history.first?.rawText == "raw transcript")
}

@MainActor
@Test func dictationFlow_consumesSignatureOverrideAfterOneDictation() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "raw transcript"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.toggleSignatureOverride()
    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)
    #expect(coordinator.signatureOverride == nil)

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(pasteboard.pastedTexts == ["raw transcript\nMade with WisprFlow", "raw transcript"])
}

@MainActor
@Test func dictationFlow_appendsSignatureAfterAICleanup() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "this is a raw test transcript"),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        chatClient: SpyChatClient(result: "Polished transcript."),
        preferencesStore: InMemoryAppPreferencesStore(
            preferences: {
                var preferences = AppPreferences()
                preferences.cleanupLevel = .medium
                preferences.signature.separator = .space
                return preferences
            }()
        )
    )

    coordinator.toggleSignatureOverride()
    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(pasteboard.pastedTexts == ["Polished transcript. Made with WisprFlow"])
}

@MainActor
@Test func coordinator_secondTogglePressClearsSignatureOverride() {
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.toggleSignatureOverride()
    coordinator.toggleSignatureOverride()

    #expect(coordinator.signatureOverride == nil)
}

@MainActor
@Test func coordinator_addsAndRemovesSignatureApps() {
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )
    let notion = SignatureApp(bundleID: "notion.id", name: "Notion")

    coordinator.addSignatureApp(notion)
    #expect(coordinator.preferences.signature.apps.contains(notion))

    // Adding the same bundle ID again — in any casing — must not duplicate the row.
    coordinator.addSignatureApp(SignatureApp(bundleID: "NOTION.ID", name: "Notion"))
    #expect(coordinator.preferences.signature.apps.filter { $0.bundleID.lowercased() == "notion.id" }.count == 1)

    coordinator.removeSignatureApp("notion.id")
    #expect(!coordinator.preferences.signature.apps.contains(notion))
}

@MainActor
@Test func coordinator_signatureHotkeyDoesNotStealDictationsLastBinding() {
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )
    coordinator.preferences.hotkeys = [.fn]

    coordinator.setSignatureHotkey(.fn)

    #expect(coordinator.preferences.hotkeys == [.fn])
    #expect(coordinator.preferences.signatureHotkey == nil)
}
