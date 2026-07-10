import AppKit
import AVFoundation
import Foundation
import os

@MainActor
final class DictationCoordinator: ObservableObject {
    private let logger = Logger(subsystem: "com.wisper-clone", category: "DictationCoordinator")
    @Published private(set) var phase: DictationPhase = .idle
    @Published private(set) var statusText = "Ready"
    @Published private(set) var lastTranscript = ""
    @Published private(set) var history: [TranscriptEntry] = []
    @Published private(set) var hasAPIKey = false
    @Published private(set) var isGlobalShortcutReady = false
    @Published private(set) var dictionaryTerms: [String] = []
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var isHandsFreeActive = false
    @Published private(set) var audioLevels: [Float] = []
    @Published var preferences = AppPreferences() {
        didSet {
            hotkeyManager.update(hotkeys: preferences.hotkeys)
            hotkeyManager.update(commandHotkey: preferences.commandHotkey)
            audioRecorder.selectedInputDeviceID = preferences.selectedInputDeviceID
            preferencesStore.savePreferences(preferences)
        }
    }
    var onRecordingStarted: (() -> Void)?

    private enum RecordingMode {
        case dictation
        case command
    }

    private var audioRecorder: AudioRecording
    private let transcriptionClient: TranscriptionServicing
    private let chatClient: ChatCompleting
    private let credentialStore: CredentialStoring
    private let paster: TextPasting
    private let notifier: UserNotifying
    private let launchAtLoginManager: LaunchAtLoginManager
    private let hotkeyManager: HotkeyManager
    private let frontmostApplicationTracker: FrontmostApplicationTracker
    private let personalDictionaryStore: PersonalDictionaryStore
    private let preferencesStore: AppPreferencesStoring
    private let historyStore: TranscriptHistoryStoring
    private let selectedTextCapturer: SelectedTextCapturing
    private let warmUpConnection: @Sendable () -> Void
    private var pasteTargetApplication: NSRunningApplication?
    private var recordingMode: RecordingMode = .dictation
    private var audioLevelTimer: Timer?
    private static let maxAudioLevelSamples = 40
    nonisolated(unsafe) private var deviceConnectedObserver: NSObjectProtocol?
    nonisolated(unsafe) private var deviceDisconnectedObserver: NSObjectProtocol?

    init(
        audioRecorder: AudioRecording = AudioRecorderService(),
        transcriptionClient: TranscriptionServicing = OpenAITranscriptionClient(),
        chatClient: ChatCompleting = OpenAIChatClient(),
        credentialStore: CredentialStoring = KeychainCredentialStore(),
        paster: TextPasting = ClipboardPaster(),
        notifier: UserNotifying = UserNotifier(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        hotkeyManager: HotkeyManager = HotkeyManager(hotkeys: [.fn, .mouse5]),
        frontmostApplicationTracker: FrontmostApplicationTracker = FrontmostApplicationTracker(),
        personalDictionaryStore: PersonalDictionaryStore = PersonalDictionaryStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        historyStore: TranscriptHistoryStoring = FileTranscriptHistoryStore(),
        selectedTextCapturer: SelectedTextCapturing = SelectedTextCapturer(),
        warmUpConnection: @escaping @Sendable () -> Void = { OpenAITranscriptionClient.warmUpConnection() }
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionClient = transcriptionClient
        self.chatClient = chatClient
        self.credentialStore = credentialStore
        self.paster = paster
        self.notifier = notifier
        self.launchAtLoginManager = launchAtLoginManager
        self.hotkeyManager = hotkeyManager
        self.frontmostApplicationTracker = frontmostApplicationTracker
        self.personalDictionaryStore = personalDictionaryStore
        self.preferencesStore = preferencesStore
        self.historyStore = historyStore
        self.selectedTextCapturer = selectedTextCapturer
        self.warmUpConnection = warmUpConnection

        hasAPIKey = ((try? credentialStore.readAPIKey()) ?? nil)?.isEmpty == false
        dictionaryTerms = personalDictionaryStore.loadTerms()
        history = historyStore.loadEntries()
        preferences = preferencesStore.loadPreferences()
        preferences.launchAtLogin = launchAtLoginManager.isEnabled
        self.audioRecorder.selectedInputDeviceID = preferences.selectedInputDeviceID
        hotkeyManager.update(hotkeys: preferences.hotkeys)
        hotkeyManager.update(commandHotkey: preferences.commandHotkey)
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
        startRecording(mode: .dictation, recordingStatusText: "Recording...")
    }

    func beginCommandRecording() {
        startRecording(mode: .command, recordingStatusText: "Listening for command...")
    }

    private func startRecording(mode: RecordingMode, recordingStatusText: String) {
        guard phase != .recording && phase != .transcribing && phase != .pasting else { return }
        guard hasAPIKey else {
            fail(DictationError.missingAPIKey)
            return
        }
        recordingMode = mode
        pasteTargetApplication = frontmostApplicationTracker.captureTargetApplication()
        warmUpConnection()

        Task {
            let granted = await audioRecorder.requestPermission()
            guard granted else {
                fail(DictationError.microphoneDenied)
                return
            }

            do {
                _ = try audioRecorder.startRecording()
                phase = .recording
                statusText = recordingStatusText
                onRecordingStarted?()
                startAudioLevelTimer()
            } catch {
                fail(error)
            }
        }
    }

    func finishRecording() {
        guard phase == .recording else { return }
        isHandsFreeActive = false
        stopAudioLevelTimer()

        phase = .transcribing
        statusText = "Transcribing..."

        let mode = recordingMode
        let clock = ContinuousClock()
        Task {
            do {
                let stopStart = clock.now
                let fileURL = try await audioRecorder.stopRecording()
                let stopDuration = clock.now - stopStart
                switch mode {
                case .dictation:
                    await transcribeAndPaste(fileURL: fileURL, stopDuration: stopDuration)
                case .command:
                    await runCommand(fileURL: fileURL, stopDuration: stopDuration)
                }
            } catch {
                fail(error)
            }
        }
    }

    func cancelRecording() {
        audioRecorder.cancelRecording()
        stopAudioLevelTimer()
        phase = .idle
        statusText = "Ready"
        isHandsFreeActive = false
        recordingMode = .dictation
    }

    func retryLastPaste() {
        guard !lastTranscript.isEmpty else { return }
        guard phase == .idle || phase == .failed else { return }

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

    func setCleanupLevel(_ level: CleanupLevel) {
        preferences.cleanupLevel = level
    }

    func setCommandHotkey(_ hotkey: Hotkey?) {
        var updated = preferences
        // Refuse to hand a hotkey to both roles: if it's the only dictation hotkey,
        // removing it would leave dictation with none, so reject the selection instead.
        if let hotkey, updated.hotkeys.count <= 1, updated.hotkeys.contains(hotkey) {
            return
        }
        updated.commandHotkey = hotkey
        if let hotkey, updated.hotkeys.count > 1 {
            updated.hotkeys.remove(hotkey)
        }
        preferences = updated
    }

    func pasteRaw(_ entry: TranscriptEntry) {
        guard phase == .idle || phase == .failed else { return }

        Task {
            await paste(entry.rawText)
        }
    }

    func copyRaw(_ entry: TranscriptEntry) {
        paster.copy(entry.rawText)
        statusText = "Copied"
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
            guard recordingMode == .dictation else { return }
            finishRecording()
        }
        hotkeyManager.onDoubleTap = { [weak self] in
            guard let self else { return }
            guard phase == .recording else { return }
            guard recordingMode == .dictation else { return }
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
        hotkeyManager.onCommandPress = { [weak self] in
            self?.beginCommandRecording()
        }
        hotkeyManager.onCommandRelease = { [weak self] in
            guard let self else { return }
            guard recordingMode == .command else { return }
            finishRecording()
        }
    }

    private func transcribeAndPaste(fileURL: URL, stopDuration: Duration) async {
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let clock = ContinuousClock()

        do {
            guard let apiKey = try credentialStore.readAPIKey(), !apiKey.isEmpty else {
                throw DictationError.missingAPIKey
            }

            let transcribeStart = clock.now
            let rawText = try await transcriptionClient.transcribe(
                fileURL: fileURL,
                apiKey: apiKey,
                prompt: transcriptionPrompt(),
                language: preferences.languageMode.apiLanguageCode
            )
            let transcribeDuration = clock.now - transcribeStart

            let cleaned = TextCleaner.clean(rawText)
            guard !cleaned.isEmpty else {
                throw DictationError.emptyTranscript
            }

            let raw = cleaned
            var final = cleaned
            var cleanupDuration = Duration.zero

            if preferences.cleanupLevel != .none {
                let tone = AppToneProfile.profile(forBundleID: pasteTargetApplication?.bundleIdentifier)
                statusText = "Polishing (\(tone.name))..."
                let bundleID = self.pasteTargetApplication?.bundleIdentifier ?? "nil"
                logger.debug("cleanup tone: \(tone.name, privacy: .public) for \(bundleID, privacy: .public)")
                let systemPrompt = CleanupPromptBuilder().buildSystemPrompt(level: preferences.cleanupLevel, tone: tone)
                let cleanupStart = clock.now
                do {
                    let polished = TextCleaner.clean(
                        try await chatClient.complete(systemPrompt: systemPrompt, userMessage: raw, apiKey: apiKey)
                    )
                    if !polished.isEmpty {
                        final = polished
                    }
                } catch {
                    logger.error("AI cleanup failed: \(error.localizedDescription, privacy: .public)")
                    notifier.notify(title: "Wisper Clone", body: "AI cleanup failed — pasted raw transcript.")
                }
                cleanupDuration = clock.now - cleanupStart
            }

            lastTranscript = final
            history.insert(TranscriptEntry(text: final, rawText: raw), at: 0)
            history = Array(history.prefix(FileTranscriptHistoryStore.maxEntries))
            historyStore.saveEntries(history)

            let pasteStart = clock.now
            await paste(final)
            let pasteDuration = clock.now - pasteStart

            logTiming(prefix: "dictation", stop: stopDuration, transcribe: transcribeDuration, middle: ("cleanup", cleanupDuration), paste: pasteDuration)
        } catch {
            fail(error)
        }
    }

    private func runCommand(fileURL: URL, stopDuration: Duration) async {
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let clock = ContinuousClock()

        do {
            guard let apiKey = try credentialStore.readAPIKey(), !apiKey.isEmpty else {
                throw DictationError.missingAPIKey
            }

            // Activate the target app before capturing the selection, then capture it
            // after the hotkey release — synthesizing ⌘C while the hotkey modifiers are
            // still held would corrupt the copy shortcut.
            await frontmostApplicationTracker.activate(pasteTargetApplication)
            let selectedText = try await selectedTextCapturer.captureSelectedText()

            let transcribeStart = clock.now
            let rawInstruction = try await transcriptionClient.transcribe(
                fileURL: fileURL,
                apiKey: apiKey,
                prompt: TranscriptionPromptBuilder().buildCommandInstructionPrompt(),
                language: preferences.languageMode.apiLanguageCode
            )
            let transcribeDuration = clock.now - transcribeStart

            let instruction = TextCleaner.clean(rawInstruction)
            guard !instruction.isEmpty else {
                throw DictationError.noInstruction
            }

            statusText = "Running command..."
            let promptBuilder = CleanupPromptBuilder()
            let systemPrompt = promptBuilder.buildCommandSystemPrompt(hasSelection: selectedText != nil)
            let userMessage = promptBuilder.buildCommandUserMessage(instruction: instruction, selectedText: selectedText)

            let chatStart = clock.now
            let rawResult = try await chatClient.complete(systemPrompt: systemPrompt, userMessage: userMessage, apiKey: apiKey)
            let chatDuration = clock.now - chatStart

            let result = TextCleaner.clean(rawResult)
            guard !result.isEmpty else {
                throw DictationError.chatCompletionFailed("Empty response")
            }

            lastTranscript = result
            history.insert(TranscriptEntry(text: result, rawText: selectedText ?? result), at: 0)
            history = Array(history.prefix(FileTranscriptHistoryStore.maxEntries))
            historyStore.saveEntries(history)

            let pasteStart = clock.now
            await paste(result)
            let pasteDuration = clock.now - pasteStart

            logTiming(prefix: "command", stop: stopDuration, transcribe: transcribeDuration, middle: ("chat", chatDuration), paste: pasteDuration)
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
        stopAudioLevelTimer()
        phase = .failed
        statusText = error.localizedDescription
        isHandsFreeActive = false
        notifier.notify(title: "Wisper Clone", body: error.localizedDescription)
    }

    private func startAudioLevelTimer() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appendAudioLevelSample()
            }
        }
    }

    private func stopAudioLevelTimer() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        audioLevels = []
    }

    private func appendAudioLevelSample() {
        guard phase == .recording else { return }
        var samples = audioLevels
        samples.append(audioRecorder.currentAudioLevel)
        if samples.count > Self.maxAudioLevelSamples {
            samples.removeFirst(samples.count - Self.maxAudioLevelSamples)
        }
        audioLevels = samples
    }

    private func transcriptionPrompt() -> String {
        TranscriptionPromptBuilder().build(dictionaryTerms: dictionaryTerms)
    }

    private func logTiming(prefix: String, stop: Duration, transcribe: Duration, middle: (label: String, duration: Duration), paste: Duration) {
        let total = stop + transcribe + middle.duration + paste
        let message = "\(prefix) timing: stop=\(formatDuration(stop)) transcribe=\(formatDuration(transcribe)) \(middle.label)=\(formatDuration(middle.duration)) paste=\(formatDuration(paste)) total=\(formatDuration(total))"
        logger.info("\(message, privacy: .public)")
    }

    private func formatDuration(_ duration: Duration) -> String {
        let components = duration.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return String(format: "%.1fs", seconds)
    }

    private func openSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
