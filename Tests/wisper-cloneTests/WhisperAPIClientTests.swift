import Foundation
import Testing
@testable import wisper_clone

@Test func openAITranscriptionClient_createsMultipartTranscriptionRequest() throws {
    let client = OpenAITranscriptionClient(
        model: "gpt-4o-transcribe",
        endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        session: .shared
    )
    let upload = AudioUpload(data: Data("audio-bytes".utf8), filename: "sample.m4a", mimeType: "audio/mp4")

    let request = client.makeRequest(
        apiKey: "test-key",
        upload: upload,
        prompt: "Product names: Wisper",
        language: "en"
    )

    #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

    let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
    #expect(contentType.hasPrefix("multipart/form-data; boundary="))

    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    #expect(body.contains(name: "model", value: "gpt-4o-transcribe"))
    #expect(body.contains(name: "response_format", value: "json"))
    #expect(body.contains(name: "temperature", value: "0"))
    #expect(body.contains(name: "language", value: "en"))
    #expect(body.contains(name: "prompt", value: "Product names: Wisper"))
    #expect(body.contains("name=\"file\""))
    #expect(body.contains("filename=\"sample.m4a\""))
    #expect(body.contains("Content-Type: audio/mp4"))
    #expect(body.contains("audio-bytes"))
}

@Test func openAITranscriptionClient_parsesSuccessfulTranscriptionResponse() async throws {
    StubURLProtocol.response = (
        data: Data(#"{"text":"Hello from Whisper Flow."}"#.utf8),
        statusCode: 200
    )
    let client = OpenAITranscriptionClient(session: makeStubbedSession())
    let audioURL = try makeTemporaryAudioFile(contents: "audio")
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let text = try await client.transcribe(
        fileURL: audioURL,
        apiKey: "test-key",
        prompt: nil,
        language: nil
    )

    #expect(text == "Hello from Whisper Flow.")
}

@Test func openAITranscriptionClient_throwsTranscriptionErrorMessageFromAPIErrorPayload() async throws {
    StubURLProtocol.response = (
        data: Data(#"{"error":{"message":"Invalid API key"}}"#.utf8),
        statusCode: 401
    )
    let client = OpenAITranscriptionClient(session: makeStubbedSession())
    let audioURL = try makeTemporaryAudioFile(contents: "audio")
    defer { try? FileManager.default.removeItem(at: audioURL) }

    do {
        _ = try await client.transcribe(fileURL: audioURL, apiKey: "bad-key", prompt: nil, language: nil)
        Issue.record("Expected transcription to fail")
    } catch let error as DictationError {
        #expect(error == .transcriptionFailed("Invalid API key"))
    }
}

@Test func openAITranscriptionClient_rejectsMissingAudioFileBeforeRequest() async throws {
    StubURLProtocol.response = (
        data: Data(#"{"text":"unused"}"#.utf8),
        statusCode: 200
    )
    let client = OpenAITranscriptionClient(session: makeStubbedSession())
    let missingURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("wisper-clone-missing-\(UUID().uuidString)")
        .appendingPathExtension("m4a")

    do {
        _ = try await client.transcribe(fileURL: missingURL, apiKey: "test-key", prompt: nil, language: nil)
        Issue.record("Expected missing audio file to fail")
    } catch let error as DictationError {
        #expect(error == .transcriptionFailed("Audio file does not exist."))
    }
}

@Test func openAITranscriptionClient_rejectsEmptyAudioFileBeforeRequest() async throws {
    let client = OpenAITranscriptionClient(session: makeStubbedSession())
    let audioURL = try makeTemporaryAudioFile(contents: "")
    defer { try? FileManager.default.removeItem(at: audioURL) }

    do {
        _ = try await client.transcribe(fileURL: audioURL, apiKey: "test-key", prompt: nil, language: nil)
        Issue.record("Expected empty audio file to fail")
    } catch let error as DictationError {
        #expect(error == .transcriptionFailed("Audio file is empty."))
    }
}

@Test func openAITranscriptionClient_rejectsOversizedAudioFileBeforeRequest() async throws {
    let client = OpenAITranscriptionClient(session: makeStubbedSession())
    let audioURL = try makeTemporaryAudioFile(contents: "audio")
    defer { try? FileManager.default.removeItem(at: audioURL) }

    let handle = try FileHandle(forWritingTo: audioURL)
    try handle.truncate(atOffset: UInt64(OpenAITranscriptionClient.maxUploadBytes + 1))
    try handle.close()

    do {
        _ = try await client.transcribe(fileURL: audioURL, apiKey: "test-key", prompt: nil, language: nil)
        Issue.record("Expected oversized audio file to fail")
    } catch let error as DictationError {
        #expect(error == .transcriptionFailed("Audio file is larger than 25 MB."))
    }
}

private extension String {
    func contains(name: String, value: String) -> Bool {
        contains("name=\"\(name)\"") && contains("\r\n\r\n\(value)\r\n")
    }
}
