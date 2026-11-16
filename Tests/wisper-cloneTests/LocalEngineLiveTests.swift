import Foundation
import Testing
@testable import wisper_clone

/// Runs the real on-device models. Off by default because it needs the downloaded
/// Parakeet model and Apple Intelligence:
///
///     WISPER_LIVE_AUDIO=/path/to/speech.m4a Scripts/run-tests.sh
private let liveAudioPath = ProcessInfo.processInfo.environment["WISPER_LIVE_AUDIO"]

/// Serialized: the models share the Neural Engine, so parallel runs distort the timings.
@Suite(.serialized)
struct LocalEngineLiveTests {
    @Test(.enabled(if: liveAudioPath != nil))
    func liveLocalEngine_transcribesAndCleansUp() async throws {
        let audioURL = URL(fileURLWithPath: try #require(liveAudioPath))
        let clock = ContinuousClock()

        let transcriber = LocalTranscriptionClient()
        let loadStart = clock.now
        try await transcriber.prepare()
        print("LIVE model load: \(clock.now - loadStart)")

        let transcribeStart = clock.now
        let raw = try await transcriber.transcribe(fileURL: audioURL, apiKey: "", model: "", prompt: nil, language: nil)
        print("LIVE transcript (\(clock.now - transcribeStart)): \(raw)")
        #expect(!raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let builder = CleanupPromptBuilder()
        for level in [CleanupLevel.light, .medium, .high] {
            let systemPrompt = builder.buildLocalSystemPrompt(level: level)
            let cleanupStart = clock.now
            let polished = try await AppleIntelligenceChatClient().complete(
                systemPrompt: systemPrompt,
                userMessage: builder.buildLocalCleanupUserMessage(transcript: raw),
                model: "",
                apiKey: ""
            )
            print("LIVE cleanup \(level.rawValue) (\(clock.now - cleanupStart)): \(polished)")
            #expect(!polished.isEmpty)
        }
    }

    /// Compares the selectable speech models with and without dictionary boosting, and times
    /// the rule-based cleanup. `WISPER_LIVE_VOCAB` is a comma-separated dictionary.
    @Test(.enabled(if: liveAudioPath != nil))
    func liveLocalEngine_comparesSpeechModelsAndBoosting() async throws {
        let audioURL = URL(fileURLWithPath: try #require(liveAudioPath))
        let vocabulary = (ProcessInfo.processInfo.environment["WISPER_LIVE_VOCAB"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let clock = ContinuousClock()
        let transcriber = LocalTranscriptionClient()

        for model in LocalSpeechModel.allCases {
            for terms in [[], vocabulary] where terms.isEmpty || !vocabulary.isEmpty {
                await transcriber.configure(model: model, vocabulary: terms)
                let loadStart = clock.now
                try await transcriber.prepare()
                let loadDuration = clock.now - loadStart

                let transcribeStart = clock.now
                let raw = try await transcriber.transcribe(fileURL: audioURL, apiKey: "", model: "", prompt: nil, language: nil)
                let label = "\(model.rawValue) boost=\(!terms.isEmpty)"
                print("LIVE \(label) load=\(loadDuration) transcribe=\(clock.now - transcribeStart): \(raw)")
                #expect(!raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                let cleanupStart = clock.now
                let tidied = FillerRemover.clean(raw)
                print("LIVE \(label) rules cleanup=\(clock.now - cleanupStart)")
                #expect(!tidied.isEmpty)
            }
        }
    }
}
