import Foundation

protocol TranscriptionServicing: Sendable {
    func transcribe(fileURL: URL, apiKey: String, prompt: String?, language: String?) async throws -> String
}

struct AudioUpload: Sendable {
    let data: Data
    let filename: String
    let mimeType: String
}

struct OpenAITranscriptionClient: TranscriptionServicing, Sendable {
    static let maxUploadBytes = 25 * 1_000 * 1_000

    let model: String
    let endpoint: URL
    let session: URLSession

    init(
        model: String = "gpt-4o-transcribe",
        endpoint: URL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        session: URLSession = .shared
    ) {
        self.model = model
        self.endpoint = endpoint
        self.session = session
    }

    func transcribe(fileURL: URL, apiKey: String, prompt: String?, language: String?) async throws -> String {
        try validateUpload(fileURL: fileURL)
        let upload = try AudioUpload(
            data: Data(contentsOf: fileURL),
            filename: fileURL.lastPathComponent,
            mimeType: mimeType(for: fileURL)
        )
        let request = makeRequest(apiKey: apiKey, upload: upload, prompt: prompt, language: language)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DictationError.transcriptionFailed("OpenAI returned an invalid response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            let message = apiError?.error.message ?? "OpenAI transcription failed with HTTP \(httpResponse.statusCode)."
            throw DictationError.transcriptionFailed(message)
        }

        let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
        return decoded.text
    }

    func makeRequest(apiKey: String, upload: AudioUpload, prompt: String?, language: String?) -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, upload: upload, prompt: prompt, language: language)
        return request
    }

    func multipartBody(boundary: String, upload: AudioUpload, prompt: String?, language: String?) -> Data {
        var body = Data()
        body.appendMultipartField(name: "model", value: model, boundary: boundary)
        body.appendMultipartField(name: "response_format", value: "json", boundary: boundary)
        body.appendMultipartField(name: "temperature", value: "0", boundary: boundary)

        if let prompt, !prompt.isEmpty {
            body.appendMultipartField(name: "prompt", value: prompt, boundary: boundary)
        }

        if let language, !language.isEmpty {
            body.appendMultipartField(name: "language", value: language, boundary: boundary)
        }

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(upload.filename)\"\r\n")
        body.append("Content-Type: \(upload.mimeType)\r\n\r\n")
        body.append(upload.data)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        default:
            return "application/octet-stream"
        }
    }

    private func validateUpload(fileURL: URL) throws {
        let path = fileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw DictationError.transcriptionFailed("Audio file does not exist.")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attributes[.size] as? NSNumber
        let byteCount = fileSize?.int64Value ?? 0

        guard byteCount > 0 else {
            throw DictationError.transcriptionFailed("Audio file is empty.")
        }

        guard byteCount <= Self.maxUploadBytes else {
            throw DictationError.transcriptionFailed("Audio file is larger than 25 MB.")
        }
    }
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
}

private struct OpenAIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }

    let error: APIError
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}
