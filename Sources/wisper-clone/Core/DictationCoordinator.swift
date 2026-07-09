import AppKit
import AVFoundation
import Foundation

@MainActor
final class DictationCoordinator: ObservableObject {
    @Published private(set) var phase: DictationPhase = .idle
    @Published private(set) var statusText = "Ready"
    @Published private(set) var lastTranscript = ""
    @Published private(set) var history: [TranscriptEntry] = []
    @Published private(set) var hasAPIKey = false
    @Published private(set) var isGlobalShortcutReady = false
    @Published private(set) var dictionaryTerms: [String] = []
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var isHandsFreeActive = false
    @Published var preferences = AppPreferences() {
        didSet {
            hotkeyManager.update(hotkeys: preferences.hotkeys)
            audioRecorder.selectedInputDeviceID = preferences.selectedInputDeviceID
            preferencesStore.savePreferences(preferences)
        }
    }
    var onRecordingStarted: (() -> Void)?

    private var audioRecorder: AudioRecording
    private let transcriptionClient: TranscriptionServicing
    private let credentialStore: CredentialStoring
    private let paster: TextPasting
    private let notifier: UserNotifying
    private let launchAtLoginManager: LaunchAtLoginManager
    private let hotkeyManager: HotkeyManager
    private let frontmostApplicationTracker: FrontmostApplicationTracker
    private let personalDictionaryStore: PersonalDictionaryStore
    private let preferencesStore: AppPreferencesStoring
    private let historyStore: TranscriptHistoryStoring
    private var pasteTargetApplication: NSRunningApplication?
    nonisolated(unsafe) private var deviceConnectedObserver: NSObjectProtocol?
    nonisolated(unsafe) private var deviceDisconnectedObserver: NSObjectProtocol?

    init(
        audioRecorder: AudioRecording = AudioRecorderService(),
        transcriptionClient: TranscriptionServicing = OpenAITranscriptionClient(),
        credentialStore: CredentialStoring = KeychainCredentialStore(),
        paster: TextPasting = ClipboardPaster(),
        notifier: UserNotifying = UserNotifier(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        hotkeyManager: HotkeyManager = HotkeyManager(hotkeys: [.fn, .mouse5]),
        frontmostApplicationTracker: FrontmostApplicationTracker = FrontmostApplicationTracker(),
        personalDictionaryStore: PersonalDictionaryStore = PersonalDictionaryStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        historyStore: TranscriptHistoryStoring = FileTranscriptHistoryStore()
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionClient = transcriptionClient
        self.credentialStore = credentialStore
        self.paster = paster
        self.notifier = notifier
        self.launchAtLoginManager = launchAtLoginManager
        self.hotkeyManager = hotkeyManager
        self.frontmostApplicationTracker = frontmostApplicationTracker
        self.personalDictionaryStore = personalDictionaryStore
        self.preferencesStore = preferencesStore
        self.historyStore = historyStore

        hasAPIKey = ((try? credentialStore.readAPIKey()) ?? nil)?.isEmpty == false
        dictionaryTerms = personalDictionaryStore.loadTerms()
        history = historyStore.loadEntries()
        preferences = preferencesStore.loadPreferences()
        preferences.launchAtLogin = launchAtLoginManager.isEnabled
        self.audioRecorder.selectedInputDeviceID = preferences.selectedInputDeviceID
        hotkeyManager.update(hotkeys: preferences.hotkeys)
        inputDevices = self.audioRecorder.availableInputDevices()
        configureHotkey()
        notifier.requestPermission()

        // Register for device hot-plug notifications with explicit MainActor hopping
        deviceConnectedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshInputDevices()
            }
        }
        deviceDisconnectedObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshInputDevices()
            }
        }
    }

    deinit {
        if let observer = deviceConnectedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = deviceDisconnectedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        hotkeyManager.start()
    }

    func stop() {
        hotkeyManager.stop()
    }

    func saveAPIKey(_ apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try credentialStore.saveAPIKey(trimmed)
            hasAPIKey = !trimmed.isEmpty
            statusText = "API key saved"
        } catch {
            fail(error)
        }
    }

    func clearAPIKey() {
        do {
            try credentialStore.deleteAPIKey()
            hasAPIKey = false
            statusText = "API key removed"
        } catch {
            fail(error)
        }
    }

    func beginRecording() {
        guard phase != .recording && phase != .transcribing && phase != .pasting else { return }
        guard hasAPIKey else {
            fail(DictationError.missingAPIKey)
            return
        }
        pasteTargetApplication = frontmostApplicationTracker.captureTargetApplication()

        Task {
            let granted = await audioRecorder.requestPermission()
            guard granted else {
                fail(DictationError.microphoneDenied)
                return
            }

            do {
                _ = try audioRecorder.startRecording()
                phase = .recording
                statusText = "Recording..."
                onRecordingStarted?()
            } catch {
                fail(error)
            }
        }
    }

    func finishRecording() {
        guard phase == .recording else { return }
        isHandsFreeActive = false

        phase = .transcribing
        statusText = "Transcribing..."

        Task {
            do {
                let fileURL = try await audioRecorder.stopRecording()
                await transcribeAndPaste(fileURL: fileURL)
            } catch {
                fail(error)
            }
        }
    }

    func cancelRecording() {
        audioRecorder.cancelRecording()
        phase = .idle
        statusText = "Ready"
        isHandsFreeActive = false
    }

    func retryLastPaste() {
        guard !lastTranscript.isEmpty else { return }

        Task {
            await paste(lastTranscript)
        }
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        paster.copy(lastTranscript)
        statusText = "Copied"
    }

    func clearSessionHistory() {
        history.removeAll()
        lastTranscript = ""
        historyStore.saveEntries(history)
    }

    func removeHistoryEntry(_ id: UUID) {
        history.removeAll { $0.id == id }
        historyStore.saveEntries(history)
    }

    func addDictionaryTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dictionaryTerms.append(trimmed)
        personalDictionaryStore.saveTerms(dictionaryTerms)
        dictionaryTerms = personalDictionaryStore.loadTerms()
        statusText = "Dictionary updated"
    }

    func removeDictionaryTerm(_ term: String) {
        let identity = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        dictionaryTerms.removeAll {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == identity
        }
        personalDictionaryStore.saveTerms(dictionaryTerms)
        dictionaryTerms = personalDictionaryStore.loadTerms()
        statusText = "Dictionary updated"
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            preferences.launchAtLogin = launchAtLoginManager.isEnabled
        } catch {
            preferences.launchAtLogin = launchAtLoginManager.isEnabled
            fail(error)
        }
    }

    func refreshInputDevices() {
        inputDevices = audioRecorder.availableInputDevices()
        if let selectedInputDeviceID = preferences.selectedInputDeviceID,
           !inputDevices.contains(where: { $0.id == selectedInputDeviceID }) {
            preferences.selectedInputDeviceID = nil
        }
    }

    func setSelectedInputDeviceID(_ id: String?) {
        preferences.selectedInputDeviceID = id
        audioRecorder.selectedInputDeviceID = id
        refreshInputDevices()
    }

    func setLanguageMode(_ mode: TranscriptionLanguageMode) {
        preferences.languageMode = mode
    }

    func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func openMicrophoneSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func configureHotkey() {
        hotkeyManager.onEventTapStatusChanged = { [weak self] ready in
            self?.isGlobalShortcutReady = ready
            if !ready {
                self?.statusText = "Allow Input Monitoring for closed-popover shortcuts."
            }
        }
        hotkeyManager.onPress = { [weak self] in
            guard let self else { return }
            if isHandsFreeActive, phase == .recording {
                finishRecording()
            } else {
                beginRecording()
            }
        }
        hotkeyManager.onRelease = { [weak self] in
            guard let self else { return }
            guard !isHandsFreeActive else { return }
            finishRecording()
        }
        hotkeyManager.onDoubleTap = { [weak self] in
            guard let self else { return }
            guard phase == .recording else { return }
            isHandsFreeActive = true
            statusText = "Recording (hands-free)..."
        }
        hotkeyManager.onEscape = { [weak self] in
            guard let self else { return }
            guard phase == .recording else { return }
            cancelRecording()
        }
        hotkeyManager.onPasteLastShortcut = { [weak self] in
            self?.retryLastPaste()
        }
    }

    private func transcribeAndPaste(fileURL: URL) async {
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        do {
            guard let apiKey = try credentialStore.readAPIKey(), !apiKey.isEmpty else {
                throw DictationError.missingAPIKey
            }

            let rawText = try await transcriptionClient.transcribe(
                fileURL: fileURL,
                apiKey: apiKey,
                prompt: transcriptionPrompt(),
                language: preferences.languageMode.apiLanguageCode
            )
            let cleaned = TextCleaner.clean(rawText)
            guard !cleaned.isEmpty else {
                throw DictationError.emptyTranscript
            }

            lastTranscript = cleaned
            history.insert(TranscriptEntry(text: cleaned), at: 0)
            history = Array(history.prefix(FileTranscriptHistoryStore.maxEntries))
            historyStore.saveEntries(history)
            await paste(cleaned)
        } catch {
            fail(error)
        }
    }

    private func paste(_ text: String) async {
        phase = .pasting
        statusText = "Pasting..."

        do {
            await frontmostApplicationTracker.activate(pasteTargetApplication)
            try await paster.paste(text)
            phase = .idle
            statusText = "Ready"
        } catch {
            paster.copy(text)
            phase = .failed
            statusText = "Copied instead of pasted"
            notifier.notify(title: "Wisper Clone", body: error.localizedDescription)
        }
    }

    private func fail(_ error: Error) {
        phase = .failed
        statusText = error.localizedDescription
        isHandsFreeActive = false
        notifier.notify(title: "Wisper Clone", body: error.localizedDescription)
    }

    private func transcriptionPrompt() -> String {
        TranscriptionPromptBuilder().build(dictionaryTerms: dictionaryTerms)
    }

    private func openSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
