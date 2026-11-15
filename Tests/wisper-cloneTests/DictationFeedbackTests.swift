import Foundation
import Testing
@testable import wisper_clone

@MainActor
@Test func feedback_signalsStartAndFinishOfADictation() async throws {
    let feedback = SpyFeedback()
    var preferences = AppPreferences()
    preferences.enableSounds = true
    preferences.enableHaptics = true
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: try makeTemporaryAudioFile(contents: "feedback")),
        transcriber: SpyTranscriptionClient(result: "done"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: nil),
        preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
        engine: .local,
        feedback: feedback
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(feedback.signals.map(\.event) == [.started, .finished])
    #expect(feedback.signals.allSatisfy { $0.sound && $0.haptic })
}

@MainActor
@Test func feedback_signalsCancelAndRespectsTheToggles() async throws {
    let feedback = SpyFeedback()
    // Both are off by default.
    let preferences = AppPreferences()
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: try makeTemporaryAudioFile(contents: "cancel")),
        transcriber: SpyTranscriptionClient(result: "unused"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: nil),
        preferencesStore: InMemoryAppPreferencesStore(preferences: preferences),
        engine: .local,
        feedback: feedback
    )

    coordinator.cancelRecording()
    #expect(feedback.signals.isEmpty)

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.cancelRecording()

    #expect(feedback.signals == [
        .init(event: .started, sound: false, haptic: false),
        .init(event: .cancelled, sound: false, haptic: false),
    ])
}

@Test func toneSynthesizer_producesShortQuietValidWavData() {
    for event in FeedbackEvent.allCases {
        let samples = ToneSynthesizer.samples(for: event)
        let data = ToneSynthesizer.wavData(for: event)

        #expect(samples.count > 4_000 && samples.count < 15_000)
        #expect(samples.allSatisfy { abs($0) <= 1 })
        #expect(abs(samples.last ?? 1) < 0.01)
        #expect(data.count == 44 + samples.count * 2)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
    }
}
