import Foundation
import Testing
@testable import wisper_clone

@Test func openAIChatClient_createsChatCompletionRequestForNonReasoningModel() throws {
    let client = OpenAIChatClient(
        endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
        session: .shared
    )

    let request = client.makeRequest(
        systemPrompt: "You are a dictation post-processor.",
        userMessage: "hello world",
        model: "gpt-4o-mini",
        apiKey: "test-key"
    )

    #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let body = try #require(request.httpBody)
    let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(decoded?["model"] as? String == "gpt-4o-mini")
    #expect(decoded?["temperature"] as? Double == 0.2)
    #expect(decoded?["reasoning_effort"] == nil)

    let messages = try #require(decoded?["messages"] as? [[String: String]])
    #expect(messages == [
        ["role": "system", "content": "You are a dictation post-processor."],
        ["role": "user", "content": "hello world"]
    ])
}

@Test func openAIChatClient_createsChatCompletionRequestForReasoningModel() throws {
    let client = OpenAIChatClient(
        endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
        session: .shared
    )

    let request = client.makeRequest(
        systemPrompt: "system",
        userMessage: "hello world",
        model: "gpt-5-mini",
        apiKey: "test-key"
    )

    let body = try #require(request.httpBody)
    let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    #expect(decoded?["model"] as? String == "gpt-5-mini")
    #expect(decoded?["temperature"] == nil)
    #expect(decoded?["reasoning_effort"] as? String == "minimal")
}

@Test func openAIChatClient_parsesSuccessfulCompletionResponse() async throws {
    let endpoint = makeStubbedEndpoint()
    StubURLProtocol.setResponse(
        (data: Data(#"{"choices":[{"message":{"content":"  Polished text. \n"}}]}"#.utf8), statusCode: 200),
        for: endpoint
    )
    let client = OpenAIChatClient(endpoint: endpoint, session: makeStubbedSession())

    let text = try await client.complete(systemPrompt: "system", userMessage: "raw", model: "gpt-4o-mini", apiKey: "test-key")

    #expect(text == "Polished text.")
}

@Test func openAIChatClient_throwsChatCompletionErrorMessageFromAPIErrorPayload() async throws {
    let endpoint = makeStubbedEndpoint()
    StubURLProtocol.setResponse(
        (data: Data(#"{"error":{"message":"boom"}}"#.utf8), statusCode: 500),
        for: endpoint
    )
    let client = OpenAIChatClient(endpoint: endpoint, session: makeStubbedSession())

    do {
        _ = try await client.complete(systemPrompt: "system", userMessage: "raw", model: "gpt-4o-mini", apiKey: "test-key")
        Issue.record("Expected completion to fail")
    } catch let error as DictationError {
        #expect(error == .chatCompletionFailed("boom"))
    }
}

@Test func openAIChatClient_fallsBackToHTTPStatusWhenErrorPayloadMissing() async throws {
    let endpoint = makeStubbedEndpoint()
    StubURLProtocol.setResponse(
        (data: Data("not json".utf8), statusCode: 503),
        for: endpoint
    )
    let client = OpenAIChatClient(endpoint: endpoint, session: makeStubbedSession())

    do {
        _ = try await client.complete(systemPrompt: "system", userMessage: "raw", model: "gpt-4o-mini", apiKey: "test-key")
        Issue.record("Expected completion to fail")
    } catch let error as DictationError {
        #expect(error == .chatCompletionFailed("HTTP 503"))
    }
}

@Test func openAIChatClient_throwsForEmptyChoices() async throws {
    let endpoint = makeStubbedEndpoint()
    StubURLProtocol.setResponse(
        (data: Data(#"{"choices":[]}"#.utf8), statusCode: 200),
        for: endpoint
    )
    let client = OpenAIChatClient(endpoint: endpoint, session: makeStubbedSession())

    do {
        _ = try await client.complete(systemPrompt: "system", userMessage: "raw", model: "gpt-4o-mini", apiKey: "test-key")
        Issue.record("Expected completion to fail")
    } catch let error as DictationError {
        #expect(error == .chatCompletionFailed("Empty response"))
    }
}

@Test func openAIChatClient_throwsForWhitespaceOnlyContent() async throws {
    let endpoint = makeStubbedEndpoint()
    StubURLProtocol.setResponse(
        (data: Data(#"{"choices":[{"message":{"content":"   \n"}}]}"#.utf8), statusCode: 200),
        for: endpoint
    )
    let client = OpenAIChatClient(endpoint: endpoint, session: makeStubbedSession())

    do {
        _ = try await client.complete(systemPrompt: "system", userMessage: "raw", model: "gpt-4o-mini", apiKey: "test-key")
        Issue.record("Expected completion to fail")
    } catch let error as DictationError {
        #expect(error == .chatCompletionFailed("Empty response"))
    }
}
