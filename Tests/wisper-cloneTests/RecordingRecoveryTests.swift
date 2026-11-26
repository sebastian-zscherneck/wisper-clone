import AVFoundation
import Foundation
import Testing
@testable import wisper_clone

/// Writes a mono 16 kHz AAC .m4a with the same settings the recorder uses.
private func makeAACRecording(seconds: Double) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("recovery-test-\(UUID().uuidString).m4a")
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let format = file.processingFormat
    let frames = AVAudioFrameCount(seconds * format.sampleRate)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(frames) {
        channel[index] = 0.3 * sin(Float(index) * 2 * .pi * 440 / Float(format.sampleRate))
    }
    try file.write(from: buffer)
    return url
}

@Test func recordingDecoder_readsAACFileAsMono16kSamples() throws {
    let url = try makeAACRecording(seconds: 2)
    defer { try? FileManager.default.removeItem(at: url) }

    let samples = try RecordingDecoder.monoSamples16k(from: url)

    // AAC adds priming and padding frames, so allow a small tolerance around 2 s.
    #expect(abs(samples.count - 32_000) < 4_000)
    #expect(samples.contains { abs($0) > 0.1 })
}

@Test func recordingDecoder_unreadableFileThrows() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("recovery-test-\(UUID().uuidString).m4a")
    try Data("not audio".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(throws: (any Error).self) {
        _ = try RecordingDecoder.monoSamples16k(from: url)
    }
}

@Test func failedRecordingArchive_movesRecordingIntoArchiveDirectory() throws {
    let source = try makeAACRecording(seconds: 0.5)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("archive-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let archived = try #require(FailedRecordingArchive(directory: directory).preserve(source))

    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: archived.path))
    #expect(archived.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
}

@Test func failedRecordingArchive_keepsOnlyTheNewestRecordings() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("archive-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let archive = FailedRecordingArchive(directory: directory, limit: 2)

    var kept: [URL] = []
    for _ in 0..<3 {
        let source = try makeAACRecording(seconds: 0.2)
        kept.append(try #require(archive.preserve(source)))
    }

    let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(remaining.count == 2)
    #expect(!FileManager.default.fileExists(atPath: kept[0].path))
    #expect(FileManager.default.fileExists(atPath: kept[2].path))
}

@MainActor
@Test func failedTranscription_keepsTheRecordingInsteadOfDeletingIt() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "two minutes of dictation")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("archive-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(error: DictationError.transcriptionFailed("short read")),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: nil),
        engine: .local,
        failedRecordingArchive: FailedRecordingArchive(directory: directory)
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.failed, in: coordinator)

    let kept = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    #expect(kept.count == 1)
    #expect(try String(contentsOf: kept[0], encoding: .utf8) == "two minutes of dictation")
}

@MainActor
@Test func successfulTranscription_stillDeletesTheRecording() async throws {
    let audioURL = try makeTemporaryAudioFile(contents: "short")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("archive-test-\(UUID().uuidString)", isDirectory: true)
    let coordinator = makeCoordinator(
        recorder: SpyRecorder(recordedFileURL: audioURL),
        transcriber: SpyTranscriptionClient(result: "hallo"),
        pasteboard: SpyPasteboard(),
        credentialStore: SpyCredentialStore(apiKey: nil),
        engine: .local,
        failedRecordingArchive: FailedRecordingArchive(directory: directory)
    )

    coordinator.beginRecording()
    try await expectPhase(.recording, in: coordinator)
    coordinator.finishRecording()
    try await expectPhase(.idle, in: coordinator)

    #expect(!FileManager.default.fileExists(atPath: audioURL.path))
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}
