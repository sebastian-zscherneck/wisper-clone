import Foundation
import Testing
@testable import wisper_clone

enum RecorderEvent: Equatable {
    case requestPermission
    case start
    case stop
    case cancel
}

struct TranscriptionRequest: Equatable {
    let fileURL: URL
    let apiKey: String
    let prompt: String?
    let language: String?
}

struct ChatCompletionRequest: Equatable {
    let systemPrompt: String
    let userMessage: String
    let apiKey: String
}

struct NotificationRecord: Equatable {
    let title: String
    let body: String
}

@MainActor
final class SpyRecorder: AudioRecording {
    private let recordedFileURL: URL
    private let permissionGranted: Bool
    var events: [RecorderEvent] = []
    var isRecording = false
    var selectedInputDeviceID: String?
    var devices: [AudioInputDevice] = []

    init(recordedFileURL: URL, permissionGranted: Bool = true) {
        self.recordedFileURL = recordedFileURL
        self.permissionGranted = permissionGranted
    }

    func requestPermission() async -> Bool {
        events.append(.requestPermission)
        return permissionGranted
    }

    func startRecording() throws -> URL {
        events.append(.start)
        isRecording = true
        return recordedFileURL
    }

    func availableInputDevices() -> [AudioInputDevice] {
        devices
    }

    func stopRecording() async throws -> URL {
        events.append(.stop)
        isRecording = false
        return recordedFileURL
    }

    func cancelRecording() {
        events.append(.cancel)
        isRecording = false
        try? FileManager.default.removeItem(at: recordedFileURL)
    }
}

final class SpyTranscriptionClient: TranscriptionServicing, @unchecked Sendable {
    private let result: String
    private let error: (any Error)?
    private let lock = NSLock()
    private var storedRequests: [TranscriptionRequest] = []

    var requests: [TranscriptionRequest] {
        lock.withLock { storedRequests }
    }

    init(result: String) {
        self.result = result
        self.error = nil
    }

    init(error: any Error) {
        self.result = ""
        self.error = error
    }

    func transcribe(fileURL: URL, apiKey: String, prompt: String?, language: String?) async throws -> String {
        lock.withLock {
            storedRequests.append(.init(fileURL: fileURL, apiKey: apiKey, prompt: prompt, language: language))
        }
        if let error {
            throw error
        }
        return result
    }
}

final class SpyChatClient: ChatCompleting, @unchecked Sendable {
    private let result: String
    private let error: (any Error)?
    private let lock = NSLock()
    private var storedRequests: [ChatCompletionRequest] = []

    var requests: [ChatCompletionRequest] {
        lock.withLock { storedRequests }
    }

    init(result: String = "") {
        self.result = result
        self.error = nil
    }

    init(error: any Error) {
        self.result = ""
        self.error = error
    }

    func complete(systemPrompt: String, userMessage: String, apiKey: String) async throws -> String {
        lock.withLock {
            storedRequests.append(.init(systemPrompt: systemPrompt, userMessage: userMessage, apiKey: apiKey))
        }
        if let error {
            throw error
        }
        return result
    }
}

final class SpyCredentialStore: CredentialStoring {
    var apiKey: String?

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func readAPIKey() throws -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
    }

    func deleteAPIKey() throws {
        apiKey = nil
    }
}

@MainActor
final class SpyPasteboard: TextPasting {
    private let pasteError: (any Error)?
    var pastedTexts: [String] = []
    var copiedTexts: [String] = []

    init(pasteError: (any Error)? = nil) {
        self.pasteError = pasteError
    }

    func paste(_ text: String) async throws {
        pastedTexts.append(text)
        if let pasteError {
            throw pasteError
        }
    }

    func copy(_ text: String) {
        copiedTexts.append(text)
    }
}

final class SpyNotifier: UserNotifying {
    var requestedPermission = false
    var notifications: [NotificationRecord] = []

    func requestPermission() {
        requestedPermission = true
    }

    func notify(title: String, body: String) {
        notifications.append(.init(title: title, body: body))
    }
}

final class InMemoryAppPreferencesStore: AppPreferencesStoring {
    var preferences: AppPreferences

    init(preferences: AppPreferences = AppPreferences()) {
        self.preferences = preferences
    }

    func loadPreferences() -> AppPreferences {
        preferences
    }

    func savePreferences(_ preferences: AppPreferences) {
        self.preferences = preferences
    }
}

final class InMemoryTranscriptHistoryStore: TranscriptHistoryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [TranscriptEntry]
    private(set) var saveCount = 0

    init(entries: [TranscriptEntry] = []) {
        self.entries = entries
    }

    func loadEntries() -> [TranscriptEntry] {
        lock.withLock { entries }
    }

    func saveEntries(_ entries: [TranscriptEntry]) {
        lock.withLock {
            self.entries = entries
            saveCount += 1
        }
    }
}

@MainActor
func makeCoordinator(
    recorder: AudioRecording,
    transcriber: TranscriptionServicing,
    pasteboard: TextPasting,
    credentialStore: CredentialStoring,
    chatClient: ChatCompleting = SpyChatClient(result: ""),
    notifier: UserNotifying = SpyNotifier(),
    historyStore: TranscriptHistoryStoring = InMemoryTranscriptHistoryStore(),
    preferencesStore: AppPreferencesStoring = InMemoryAppPreferencesStore(),
    hotkeyManager: HotkeyManager = HotkeyManager(hotkeys: [.fn, .mouse5])
) -> DictationCoordinator {
    DictationCoordinator(
        audioRecorder: recorder,
        transcriptionClient: transcriber,
        chatClient: chatClient,
        credentialStore: credentialStore,
        paster: pasteboard,
        notifier: notifier,
        launchAtLoginManager: LaunchAtLoginManager(),
        hotkeyManager: hotkeyManager,
        preferencesStore: preferencesStore,
        historyStore: historyStore
    )
}

@MainActor
func expectPhase(
    _ expected: DictationPhase,
    in coordinator: DictationCoordinator,
    timeout: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let start = ContinuousClock.now
    while coordinator.phase != expected {
        if ContinuousClock.now - start > timeout {
            Issue.record(
                "Expected phase \(expected), got \(coordinator.phase)",
                sourceLocation: sourceLocation
            )
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
func expectPasteCount(
    _ expected: Int,
    in pasteboard: SpyPasteboard,
    timeout: Duration = .seconds(2),
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    let start = ContinuousClock.now
    while pasteboard.pastedTexts.count != expected {
        if ContinuousClock.now - start > timeout {
            Issue.record(
                "Expected \(expected) pasted texts, got \(pasteboard.pastedTexts.count)",
                sourceLocation: sourceLocation
            )
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

func makeTemporaryAudioFile(contents: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wisper-clone-test-\(UUID().uuidString)")
        .appendingPathExtension("m4a")
    try Data(contents.utf8).write(to: url)
    return url
}

func makeStubbedEndpoint() -> URL {
    URL(string: "https://stub.invalid/\(UUID().uuidString)")!
}

func makeStubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

final class StubURLProtocol: URLProtocol {
    // Responses are keyed by request URL so parallel tests never race on
    // shared stub state — each test registers its own unique endpoint.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [URL: (data: Data, statusCode: Int)] = [:]

    static func setResponse(_ response: (data: Data, statusCode: Int), for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        responses[url] = response
    }

    private static func response(for url: URL) -> (data: Data, statusCode: Int)? {
        lock.lock()
        defer { lock.unlock() }
        return responses[url]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let response = Self.response(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
