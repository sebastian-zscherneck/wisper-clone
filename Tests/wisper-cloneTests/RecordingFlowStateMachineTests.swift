import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func dictationFlow_recordsTranscribesCleansAndPastes() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let recorder = SpyRecorder(recordedFileURL: audioURL)
    let transcriber = SpyTranscriptionClient(result: "  hello   world ! \n")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: transcriber,
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    #expect(coordinator.phase == .idle)

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    #expect(recorder.events == [.requestPermission, .start])

    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(recorder.events == [.requestPermission, .start, .stop])
    #expect(transcriber.requests == [
        .init(
            fileURL: audioURL,
            apiKey: "test-key",
            model: "gpt-4o-transcribe",
            prompt: """
            Transcribe this as polished personal dictation.
            The speaker frequently mixes German and English, often switching within the same sentence.
            Write every word in the language it was spoken in - never translate, never normalize a sentence to one language.
            Purely English speech must produce purely English text, purely German speech purely German text.
            Examples of the expected style: "Ich habe den n8n workflow gestern deployed und die error rate ist deutlich runter." / "Let's ship the update today, das Testing machen wir morgen."
            Preserve the spoken language and meaning of each phrase; do not translate or add facts.
            Lightly smooth filler words, repeated words, obvious false starts, and minor spoken disfluencies.
            Use natural punctuation, capitalization, and short paragraphs for readability.
            If the speaker lists multiple items, format them as a concise bullet list.
            Keep short messages short and natural; do not make casual messages overly formal.
            Keep proper nouns, product names, acronyms, and technical terms exactly when they match the audio.
            Preferred vocabulary and spellings: n8n; Claude; Sebastian Zscherneck. Use these exact spellings only when they match the audio.
            """,
            language: nil
        )
    ])
    #expect(coordinator.lastTranscript == "hello world!")
    #expect(coordinator.history.map(\.text) == ["hello world!"])
    #expect(pasteboard.pastedTexts == ["hello world!"])
}

@MainActor
@Test func dictationFlow_requiresAPIKeyBeforeRecording() async throws {
    let recorder = SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a"))
    let notifier = SpyNotifier()
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: nil),
        notifier: notifier
    )

    coordinator.beginRecording()

    #expect(coordinator.phase == .failed)
    #expect(recorder.events.isEmpty)
    #expect(notifier.notifications == [
        .init(title: "Wisper Clone", body: DictationError.missingAPIKey.localizedDescription)
    ])
}

@MainActor
@Test func dictationFlow_ignoresFinishWhenNotRecording() async throws {
    let transcriber = SpyTranscriptionClient(result: "unused")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: URL(filePath: "/tmp/not-used.m4a")),
        transcriber: transcriber,
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.finishRecording()

    #expect(coordinator.phase == .idle)
    #expect(transcriber.requests.isEmpty)
    #expect(pasteboard.pastedTexts.isEmpty)
}

@MainActor
@Test func dictationFlow_silentRecordingIsNeverTranscribed() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let recorder = SpyRecorder(recordedFileURL: audioURL)
    recorder.currentAudioLevel = 0.0
    let transcriber = SpyTranscriptionClient(result: "hallucinated prompt echo")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: transcriber,
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    try await expectAudioLevelsNonEmpty(in: coordinator)

    coordinator.finishRecording()
    try await expectPhase(.failed, in: coordinator)

    #expect(transcriber.requests.isEmpty)
    #expect(pasteboard.pastedTexts.isEmpty)
}

@MainActor
@Test func dictationFlow_fillsAudioLevelsWhileRecordingAndClearsOnFinish() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let recorder = SpyRecorder(recordedFileURL: audioURL)
    recorder.currentAudioLevel = 0.5
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: SpyTranscriptionClient(result: "hello"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    #expect(coordinator.audioLevels.isEmpty)

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    try await expectAudioLevelsNonEmpty(in: coordinator)
    #expect(coordinator.audioLevels.allSatisfy { $0 == 0.5 })

    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)
    #expect(coordinator.audioLevels.isEmpty)
}

@MainActor
@Test func dictationFlow_clearsAudioLevelsOnCancel() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let recorder = SpyRecorder(recordedFileURL: audioURL)
    recorder.currentAudioLevel = 0.8
    let coordinator = makeCoordinator(
        recorder: recorder,
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key")
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    try await expectAudioLevelsNonEmpty(in: coordinator)

    coordinator.cancelRecording()

    #expect(coordinator.audioLevels.isEmpty)
}

@MainActor
@Test(arguments: [
    (TranscriptionQuality.accurate, "gpt-4o-transcribe"),
    (TranscriptionQuality.fast, "gpt-4o-mini-transcribe")
])
func dictationFlow_usesModelForSelectedTranscriptionQuality(quality: TranscriptionQuality, expectedModel: String) async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "fake audio")
    let transcriber = SpyTranscriptionClient(result: "hello")
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: transcriber,
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        preferencesStore: InMemoryAppPreferencesStore(
            preferences: {
                var preferences = AppPreferences()
                preferences.transcriptionQuality = quality
                return preferences
            }()
        )
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(transcriber.requests.first?.model == expectedModel)
}
