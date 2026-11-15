import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func localEngine_dictatesWithoutAPIKey() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "local")
    let transcriber = SpyTranscriptionClient(result: "lokal diktiert")
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: transcriber,
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: nil),
        engine: .local
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(pasteboard.pastedTexts == ["lokal diktiert"])
    #expect(transcriber.requests.map(\.apiKey) == [""])
}

@MainActor
@Test func openAIEngine_stillRequiresAPIKey() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "remote")
    let notifier = SpyNotifier()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: nil),
        notifier: notifier,
        engine: .openAI
    )

    coordinator.beginRecording()
    try await expectPhase(.failed, in: coordinator)
}

@MainActor
@Test func localEngine_usesLocalClientsNotOpenAIClients() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "routing")
    let remoteTranscriber = SpyTranscriptionClient(result: "remote")
    let localTranscriber = SpyTranscriptionClient(result: "local")
    let pasteboard = SpyPasteboard()
    let preferencesStore = InMemoryAppPreferencesStore()
    let coordinator = DictationCoordinator(
        audioRecorder: SpyRecorder(recordedFileURL: audioURL),
        transcriptionClient: remoteTranscriber,
        chatClient: SpyChatClient(result: ""),
        localTranscriptionClient: localTranscriber,
        localChatClient: SpyChatClient(result: ""),
        credentialStore: SpyCredentialStore(apiKey: "test-key"),
        paster: pasteboard,
        notifier: SpyNotifier(),
        personalDictionaryStore: PersonalDictionaryStore(defaults: UserDefaults(suiteName: "wisper-clone-test-dictionary-\(UUID().uuidString)")!),
        personalRulesStore: PersonalRulesStore(defaults: UserDefaults(suiteName: "wisper-clone-test-rules-\(UUID().uuidString)")!),
        preferencesStore: preferencesStore,
        historyStore: InMemoryTranscriptHistoryStore(),
        selectedTextCapturer: SpySelectedTextCapturer(),
        feedback: SpyFeedback(),
        warmUpConnection: {}
    )
    coordinator.minimumRecordingDuration = .zero

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(pasteboard.pastedTexts == ["local"])
    #expect(remoteTranscriber.requests.isEmpty)

    coordinator.setEngine(.openAI)
    #expect(preferencesStore.preferences.engine == .openAI)
}

@MainActor
private func dictate(_ coordinator: DictationCoordinator, expecting phase: DictationPhase) async throws {
    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(phase, in: coordinator)
}

@MainActor
@Test func localEngine_correctsDictionaryTermsWithoutCleanup() async throws {
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: try makeTemporaryAudioFile(contents: "names")),
        transcriber: SpyTranscriptionClient(result: "Die Flobar ist zu groß."),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: nil),
        engine: .local
    )
    coordinator.addDictionaryTerm("Flow Bar")

    try await dictate(coordinator, expecting: .idle)

    #expect(pasteboard.pastedTexts == ["Die Flow Bar ist zu groß."])
}

@MainActor
@Test func localEngine_rejectsTranscriptInWrongScriptAndClearsTheFailure() async throws {
    let pasteboard = SpyPasteboard()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: try makeTemporaryAudioFile(contents: "script")),
        transcriber: SpyTranscriptionClient(result: "Тест, тест, тест."),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: nil),
        engine: .local
    )
    coordinator.failureDisplayDuration = .milliseconds(50)

    try await dictate(coordinator, expecting: .failed)

    #expect(pasteboard.pastedTexts.isEmpty)
    #expect(coordinator.statusText == DictationError.unrecognizedLanguage.errorDescription)
    try await expectPhase(.idle, in: coordinator)
    #expect(coordinator.statusText == "Ready")
}

@MainActor
@Test func localEngine_keepsSpokenWordsWhenCleanupRewordsThem() async throws {
    let raw = "Zudem sind einige Wörter falsch, überleg mal woran das liegen könnte."
    let pasteboard = SpyPasteboard()
    var preferences = AppPreferences()
    preferences.cleanupLevel = .light
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: try makeTemporaryAudioFile(contents: "reworded")),
        transcriber: SpyTranscriptionClient(result: raw),
        pasteboard: pasteboard,
        credentialStore: SpyCredentialStore(apiKey: nil),
        chatClient: SpyChatClient(result: "Darüber hinaus sind einige Wörter falsch, überleg mal woran das liegen könnte."),
        preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
        engine: .local
    )

    try await dictate(coordinator, expecting: .idle)

    #expect(pasteboard.pastedTexts == [raw])
}
