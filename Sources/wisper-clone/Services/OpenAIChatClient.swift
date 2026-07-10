import Foundation

protocol ChatCompleting: Sendable {
    func complete(systemPrompt: String, userMessage: String, apiKey: String) async throws -> String
}

struct OpenAIChatClient: ChatCompleting, Sendable {
    let model: String
    let endpoint: URL
    let session: URLSession

    init(
        model: String = "gpt-4o-mini",
        endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        session: URLSession = .shared
    ) {
        self.model = model
        self.endpoint = endpoint
        self.session = session
    }

    func complete(systemPrompt: String, userMessage: String, apiKey: String) async throws -> String {
        let request = makeRequest(systemPrompt: systemPrompt, userMessage: userMessage, apiKey: apiKey)
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

    func makeRequest(systemPrompt: String, userMessage: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OpenAIChatRequestBody(
            model: model,
            temperature: 0.2,
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
    let temperature: Double
    let messages: [Message]
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
