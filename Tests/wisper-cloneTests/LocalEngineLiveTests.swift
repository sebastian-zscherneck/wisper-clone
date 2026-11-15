import Foundation
import Testing
@testable import wisper_clone

/// Runs the real on-device models. Off by default because it needs the downloaded
/// Parakeet model and Apple Intelligence:
///
///     WISPER_LIVE_AUDIO=/path/to/speech.m4a Scripts/run-tests.sh
private let liveAudioPath = ProcessInfo.processInfo.environment["WISPER_LIVE_AUDIO"]

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
