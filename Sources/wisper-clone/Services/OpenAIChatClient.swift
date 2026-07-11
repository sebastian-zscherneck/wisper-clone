import Foundation

protocol ChatCompleting: Sendable {
    func complete(systemPrompt: String, userMessage: String, model: String, apiKey: String) async throws -> String
}

struct OpenAIChatClient: ChatCompleting, Sendable {
    /// Model used for the dictation cleanup pass (fast, cheap).
    static let cleanupModel = "gpt-4o-mini"
    /// Model used for the command mode edit/generate pass (stronger reasoning).
    static let commandModel = "gpt-5.4-mini"

    let endpoint: URL
    let session: URLSession

    init(
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    func complete(systemPrompt: String, userMessage: String, model: String, apiKey: String) async throws -> String {
        let request = makeRequest(systemPrompt: systemPrompt, userMessage: userMessage, model: model, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DictationError.chatCompletionFailed("OpenAI returned an invalid response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIChatErrorResponse.self, from: data)
            let message = apiError?.error.message ?? "HTTP \(httpResponse.statusCode)"
            throw DictationError.chatCompletionFailed(message)
        }

        guard let decoded = try? JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw DictationError.chatCompletionFailed("Empty response")
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DictationError.chatCompletionFailed("Empty response")
        }

        return trimmed
    }

    func makeRequest(systemPrompt: String, userMessage: String, model: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // gpt-5 family models only accept the default temperature and expose a
        // reasoning_effort knob instead; older models keep the fixed temperature.
        // "none" is the lowest effort accepted since gpt-5.1 (which removed
        // "minimal") and keeps command mode latency low.
        let isReasoningModel = model.hasPrefix("gpt-5")
        let body = OpenAIChatRequestBody(
            model: model,
            temperature: isReasoningModel ? nil : 0.2,
            reasoningEffort: isReasoningModel ? "none" : nil,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userMessage)
            ]
        )
        request.httpBody = try? JSONEncoder().encode(body)
        return request
    }
}

private struct OpenAIChatRequestBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let temperature: Double?
    let reasoningEffort: String?
    let messages: [Message]

    private enum CodingKeys: String, CodingKey {
        case model, temperature, messages
        case reasoningEffort = "reasoning_effort"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(messages, forKey: .messages)
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct OpenAIChatErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}
