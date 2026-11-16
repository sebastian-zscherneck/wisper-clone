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
    @Published private(set) var localModelState: LocalModelState = .notLoaded
    @Published private(set) var isGlobalShortcutReady = false
    @Published private(set) var dictionaryTerms: [String] = []
    @Published private(set) var rules: [String] = []
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var isHandsFreeActive = false
    @Published private(set) var isCommandRecording = false
    @Published private(set) var audioLevels: [Float] = []
    @Published private(set) var hotkeyCaptureTarget: HotkeyCaptureTarget?
    /// Overrides the per-app signature rule for the next dictation only.
    /// `nil` follows the configured apps; `true`/`false` force it on/off once.
    @Published private(set) var signatureOverride: Bool?
    @Published var preferences = AppPreferences() {
        didSet {
            hotkeyManager.update(hotkeys: preferences.hotkeys)
            hotkeyManager.update(commandHotkey: preferences.commandHotkey)
            hotkeyManager.update(signatureHotkey: preferences.signatureHotkey)
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
    private let localTranscriptionClient: TranscriptionServicing
    private let localChatClient: ChatCompleting
    private let credentialStore: CredentialStoring
    private let paster: TextPasting
    private let notifier: UserNotifying
    private let launchAtLoginManager: LaunchAtLoginManager
    private let hotkeyManager: HotkeyManager
    private let frontmostApplicationTracker: FrontmostApplicationTracker
    private let personalDictionaryStore: PersonalDictionaryStore
    private let personalRulesStore: PersonalRulesStore
    private let preferencesStore: AppPreferencesStoring
    private let historyStore: TranscriptHistoryStoring
    private let selectedTextCapturer: SelectedTextCapturing
    private let feedback: DictationFeedbackProviding
    private let warmUpConnection: @Sendable () -> Void
    private var pasteTargetApplication: NSRunningApplication?
    private var pasteTargetWindowTitle: String?
    private var captureGeneration = 0
    private var recordingMode: RecordingMode = .dictation
    private var audioLevelTimer: Timer?
    private var recordingPeakLevel: Float = 0
    private var recordingStartedAt: ContinuousClock.Instant?
    /// `phase` switches to `.recording` with the key press; this turns true once audio is
    /// actually being captured.
    var isMicrophoneOpen: Bool { phase == .recording && recordingStartedAt != nil }
    // Recordings shorter than this are discarded without any transcription or output:
    // accidental hotkey taps produce silent/near-empty audio that Whisper-family models
    // answer with hallucinated prompt content. Internal so tests can lower it.
    var minimumRecordingDuration: Duration = .seconds(1)
    /// How long a failure stays on screen before the app returns to idle.
    var failureDisplayDuration: Duration = .seconds(4)
    private var failureGeneration = 0
    private var localModelGeneration = 0
    private var recordingLevelSampleCount = 0
    private static let maxAudioLevelSamples = 40
    // Below this normalized peak level a recording is treated as silence. Whisper-family
    // models hallucinate prompt content (e.g. dictionary terms) on silent audio, so
    // silent recordings must never reach the API.
    private static let silencePeakThreshold: Float = 0.05
    private static let maxSelectionWords = 1_000
    /// Short confirmations ("ja passt danke") don't need AI polishing —
    /// skipping the chat call saves latency and cost.
    private static let minimumWordsForCleanup = 6
    private static let ruleTriggerPrefixes = [
        "merke dir als regel",
        "merk dir als regel",
        "neue regel",
        "add a rule",
        "remember the rule",
        "save the rule"
    ]
    nonisolated(unsafe) private var deviceConnectedObserver: NSObjectProtocol?
    nonisolated(unsafe) private var deviceDisconnectedObserver: NSObjectProtocol?

    init(
        audioRecorder: AudioRecording = AudioRecorderService(),
        transcriptionClient: TranscriptionServicing = OpenAITranscriptionClient(),
        chatClient: ChatCompleting = OpenAIChatClient(),
        localTranscriptionClient: TranscriptionServicing = LocalTranscriptionClient(),
        localChatClient: ChatCompleting = AppleIntelligenceChatClient(),
        credentialStore: CredentialStoring = KeychainCredentialStore(),
        paster: TextPasting = ClipboardPaster(),
        notifier: UserNotifying = UserNotifier(),
        launchAtLoginManager: LaunchAtLoginManager = LaunchAtLoginManager(),
        hotkeyManager: HotkeyManager = HotkeyManager(hotkeys: [.fn, .mouse5]),
        frontmostApplicationTracker: FrontmostApplicationTracker = FrontmostApplicationTracker(),
        personalDictionaryStore: PersonalDictionaryStore = PersonalDictionaryStore(),
        personalRulesStore: PersonalRulesStore = PersonalRulesStore(),
        preferencesStore: AppPreferencesStoring = UserDefaultsAppPreferencesStore(),
        historyStore: TranscriptHistoryStoring = FileTranscriptHistoryStore(),
        selectedTextCapturer: SelectedTextCapturing = SelectedTextCapturer(),
        feedback: DictationFeedbackProviding? = nil,
        warmUpConnection: @escaping @Sendable () -> Void = { OpenAITranscriptionClient.warmUpConnection() }
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionClient = transcriptionClient
        self.chatClient = chatClient
        self.localTranscriptionClient = localTranscriptionClient
        self.localChatClient = localChatClient
        self.credentialStore = credentialStore
        self.paster = paster
        self.notifier = notifier
        self.launchAtLoginManager = launchAtLoginManager
        self.hotkeyManager = hotkeyManager
        self.frontmostApplicationTracker = frontmostApplicationTracker
        self.personalDictionaryStore = personalDictionaryStore
        self.personalRulesStore = personalRulesStore
        self.preferencesStore = preferencesStore
        self.historyStore = historyStore
        self.selectedTextCapturer = selectedTextCapturer
        self.feedback = feedback ?? DictationFeedback()
        self.warmUpConnection = warmUpConnection

        dictionaryTerms = personalDictionaryStore.loadTerms()
        rules = personalRulesStore.loadRules()
        history = historyStore.loadEntries()
        preferences = preferencesStore.loadPreferences()
        refreshAPIKeyState()
        preferences.launchAtLogin = launchAtLoginManager.isEnabled
        self.audioRecorder.selectedInputDeviceID = preferences.selectedInputDeviceID
        hotkeyManager.update(hotkeys: preferences.hotkeys)
        hotkeyManager.update(commandHotkey: preferences.commandHotkey)
        hotkeyManager.update(signatureHotkey: preferences.signatureHotkey)
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
        prepareLocalModelsIfNeeded()
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
        guard preferences.engine == .local || hasAPIKey else {
            fail(DictationError.missingAPIKey)
            return
        }
        recordingMode = mode
        isCommandRecording = (mode == .command)
        let targetApplication = frontmostApplicationTracker.captureTargetApplication()
        pasteTargetApplication = targetApplication
        pasteTargetWindowTitle = nil
        if preferences.engine == .openAI {
            warmUpConnection()
        } else if mode == .dictation, preferences.cleanupLevel != .none,
                  preferences.localCleanupEngine == .appleIntelligence,
                  let prewarming = localChatClient as? ChatPrewarming {
            // Load the cleanup prompt into the on-device model while the user is still
            // speaking, so the cleanup itself starts without a cold start.
            prewarming.prewarm(systemPrompt: localCleanupSystemPrompt())
        }

        // The window title is only needed at cleanup time (for tone detection), not to
        // start recording, so resolve it off the synchronous hot path. If it hasn't
        // resolved (or fails) by the time cleanup reads it, pasteTargetWindowTitle stays
        // nil — same fails-closed behavior as before. The generation token prevents a
        // slow title lookup from an earlier recording overwriting a newer capture.
        captureGeneration += 1
        let generation = captureGeneration
        Task {
            let title = await frontmostApplicationTracker.windowTitle(for: targetApplication)
            if generation == captureGeneration {
                pasteTargetWindowTitle = title
            }
        }

        // The Flow Bar follows `phase`, so switch it with the key press itself. Opening the
        // microphone takes a moment and must not delay the visible reaction.
        recordingStartedAt = nil
        phase = .recording
        statusText = recordingStatusText

        Task {
            let granted = await audioRecorder.requestPermission()
            guard generation == captureGeneration, phase == .recording else { return }
            guard granted else {
                fail(DictationError.microphoneDenied)
                return
            }

            do {
                _ = try await audioRecorder.startRecording()
                guard generation == captureGeneration, phase == .recording else {
                    // Released or cancelled while the microphone was still opening.
                    if phase == .idle || phase == .failed {
                        audioRecorder.cancelRecording()
                    }
                    return
                }
                signal(.started)
                recordingStartedAt = .now
                onRecordingStarted?()
                startAudioLevelTimer()
            } catch {
                // After a release or cancel the aborted start is expected, not a failure.
                guard generation == captureGeneration, phase == .recording else { return }
                fail(error)
            }
        }
    }

    func finishRecording() {
        guard phase == .recording else { return }
        isHandsFreeActive = false
        stopAudioLevelTimer()

        guard let startedAt = recordingStartedAt else {
            discardRecording(reason: "released before the microphone opened")
            return
        }
        if ContinuousClock.now - startedAt < minimumRecordingDuration {
            discardRecording(reason: "below minimum duration")
            return
        }

        phase = .transcribing
        statusText = "Transcribing..."
        signal(.finished)

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
        if phase == .recording {
            signal(.cancelled)
        }
        audioRecorder.cancelRecording()
        stopAudioLevelTimer()
        phase = .idle
        statusText = "Ready"
        isHandsFreeActive = false
        isCommandRecording = false
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
        prepareLocalModelsIfNeeded(reload: true)
        statusText = "Dictionary updated"
    }

    func removeDictionaryTerm(_ term: String) {
        let identity = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        dictionaryTerms.removeAll {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == identity
        }
        personalDictionaryStore.saveTerms(dictionaryTerms)
        dictionaryTerms = personalDictionaryStore.loadTerms()
        prepareLocalModelsIfNeeded(reload: true)
        statusText = "Dictionary updated"
    }

    func addRule(_ rule: String) {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rules.append(trimmed)
        personalRulesStore.saveRules(rules)
        rules = personalRulesStore.loadRules()
        statusText = "Rules updated"
    }

    func removeRule(_ rule: String) {
        let identity = rule.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        rules.removeAll {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == identity
        }
        personalRulesStore.saveRules(rules)
        rules = personalRulesStore.loadRules()
        statusText = "Rules updated"
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

    func setTranscriptionQuality(_ quality: TranscriptionQuality) {
        preferences.transcriptionQuality = quality
    }

    func setCommandHotkey(_ hotkey: HotkeyBinding?) {
        var updated = preferences
        // Refuse to hand a hotkey to both roles: if it's the only dictation hotkey,
        // removing it would leave dictation with none, so reject the selection instead.
        if let hotkey, updated.hotkeys.count <= 1, updated.hotkeys.contains(hotkey) {
            return
        }
        updated.commandHotkey = hotkey
        if let hotkey, updated.hotkeys.count > 1 {
            updated.hotkeys.removeAll { $0 == hotkey }
        }
        preferences = updated
    }

    func setSignatureHotkey(_ hotkey: HotkeyBinding?) {
        var updated = preferences
        // Same rule as the command hotkey: never take dictation's last binding away.
        if let hotkey, updated.hotkeys.count <= 1, updated.hotkeys.contains(hotkey) {
            return
        }
        updated.signatureHotkey = hotkey
        if let hotkey {
            if updated.hotkeys.count > 1 {
                updated.hotkeys.removeAll { $0 == hotkey }
            }
            if updated.commandHotkey == hotkey {
                updated.commandHotkey = nil
            }
        }
        preferences = updated
    }

    // MARK: - Signature

    func setSignatureAutoAppendEnabled(_ enabled: Bool) {
        preferences.signature.isAutoAppendEnabled = enabled
    }

    func setSignatureText(_ text: String) {
        preferences.signature.text = text
    }

    func setSignatureSeparator(_ separator: SignatureSeparator) {
        preferences.signature.separator = separator
    }

    func addSignatureApp(_ app: SignatureApp) {
        let identity = app.bundleID.lowercased()
        guard !identity.isEmpty else { return }
        guard !preferences.signature.apps.contains(where: { $0.bundleID.lowercased() == identity }) else { return }
        var updated = preferences
        updated.signature.apps.append(app)
        preferences = updated
    }

    func removeSignatureApp(_ bundleID: String) {
        let identity = bundleID.lowercased()
        var updated = preferences
        updated.signature.apps.removeAll { $0.bundleID.lowercased() == identity }
        preferences = updated
    }

    /// Apps offered in the "Add app" menu: everything with a Dock icon right now, plus the
    /// built-in suggestions so an app can be configured while it is closed. Already
    /// configured apps are filtered out.
    func availableSignatureApps() -> [SignatureApp] {
        let configured = Set(preferences.signature.apps.map { $0.bundleID.lowercased() })
        let ownProcessIdentifier = NSRunningApplication.current.processIdentifier
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownProcessIdentifier }
            .compactMap { application -> SignatureApp? in
                guard let bundleID = application.bundleIdentifier, let name = application.localizedName else {
                    return nil
                }
                return SignatureApp(bundleID: bundleID, name: name)
            }

        var seen = Set<String>()
        return (running + SignatureApp.suggestions)
            .filter { app in
                let identity = app.bundleID.lowercased()
                return !configured.contains(identity) && seen.insert(identity).inserted
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Flips the signature decision for the next dictation and back. Reads the app that is
    /// frontmost *now*, so pressing the hotkey in Slack (where the signature is already on)
    /// turns it off once, and pressing it anywhere else turns it on once.
    func toggleSignatureOverride() {
        guard signatureOverride == nil else {
            signatureOverride = nil
            statusText = "Signature: following app rules"
            return
        }

        let target = frontmostApplicationTracker.captureTargetApplication()
        let wouldAppend = SignatureAppender.shouldAppend(
            settings: preferences.signature,
            bundleID: target?.bundleIdentifier
        )
        signatureOverride = !wouldAppend
        statusText = wouldAppend ? "Signature off for next dictation" : "Signature on for next dictation"
    }

    // MARK: - Hotkey capture ("click the field, press your shortcut")

    enum HotkeyCaptureTarget: Equatable {
        /// Replace the dictation binding at `index`; `nil` appends a new one.
        case dictation(index: Int?)
        case command
        case signature
    }

    func beginHotkeyCapture(for target: HotkeyCaptureTarget) {
        hotkeyCaptureTarget = target
        statusText = "Press your shortcut… (Esc to cancel)"
        hotkeyManager.beginCapture { [weak self] event in
            self?.handleCaptureEvent(event)
        }
    }

    func cancelHotkeyCapture() {
        guard hotkeyCaptureTarget != nil else { return }
        hotkeyManager.cancelCapture()
    }

    func removeDictationHotkey(at index: Int) {
        guard preferences.hotkeys.indices.contains(index), preferences.hotkeys.count > 1 else { return }
        var updated = preferences
        updated.hotkeys.remove(at: index)
        preferences = updated
    }

    private func handleCaptureEvent(_ event: HotkeyCaptureEvent) {
        switch event {
        case .rejected:
            statusText = "Add a modifier to that key"
        case .cancelled:
            hotkeyCaptureTarget = nil
            statusText = "Ready"
        case .captured(let binding):
            guard let target = hotkeyCaptureTarget else { return }
            hotkeyCaptureTarget = nil
            apply(binding, to: target)
        }
    }

    private func apply(_ binding: HotkeyBinding, to target: HotkeyCaptureTarget) {
        var updated = preferences

        let replacedSlot: HotkeyBinding?
        switch target {
        case .dictation(let index):
            replacedSlot = index.flatMap { updated.hotkeys.indices.contains($0) ? updated.hotkeys[$0] : nil }
        case .command:
            replacedSlot = updated.commandHotkey
        case .signature:
            replacedSlot = updated.signatureHotkey
        }

        let takenElsewhere = (updated.hotkeys.contains(binding)
            || updated.commandHotkey == binding
            || updated.signatureHotkey == binding)
            && binding != replacedSlot
        if takenElsewhere {
            statusText = "\(binding.displayName) is already in use"
            return
        }

        switch target {
        case .dictation(let index):
            if let index, updated.hotkeys.indices.contains(index) {
                updated.hotkeys[index] = binding
            } else {
                updated.hotkeys.append(binding)
            }
        case .command:
            updated.commandHotkey = binding
        case .signature:
            updated.signatureHotkey = binding
        }

        preferences = updated
        statusText = "Hotkey set to \(binding.displayName)"
    }

    func pasteRaw(_ entry: TranscriptEntry) {
        guard phase == .idle || phase == .failed else { return }

        Task {
            await paste(entry.rawText)
        }
    }

    func copy(_ entry: TranscriptEntry) {
        paster.copy(entry.text)
        statusText = "Copied"
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
                self?.statusText = "Allow Input Monitoring for global shortcuts."
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
        hotkeyManager.onSignaturePress = { [weak self] in
            self?.toggleSignatureOverride()
        }
    }

    private func transcribeAndPaste(fileURL: URL, stopDuration: Duration) async {
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let clock = ContinuousClock()

        do {
            if recordingWasSilent {
                logger.debug("recording skipped: no audio above silence threshold")
                throw DictationError.emptyTranscript
            }
            let engine = try resolveEngine()

            let transcribeStart = clock.now
            let prompt = transcriptionPrompt()
            let rawText = try await engine.transcriber.transcribe(
                fileURL: fileURL,
                apiKey: engine.apiKey,
                model: preferences.transcriptionQuality.modelName,
                prompt: prompt,
                language: preferences.languageMode.apiLanguageCode
            )
            let transcribeDuration = clock.now - transcribeStart

            let isLocal = preferences.engine == .local
            if isLocal, TranscriptChecks.isMostlyNonLatin(rawText) {
                logger.debug("transcript discarded: wrong script from local speech model")
                throw DictationError.unrecognizedLanguage
            }
            let cleaned = DictionaryCorrector.apply(TextCleaner.clean(rawText), terms: dictionaryTerms)
            guard !cleaned.isEmpty else {
                throw DictationError.emptyTranscript
            }
            // Whisper-family models echo prompt fragments (dictionary terms, example
            // sentences) when the audio contains no usable speech. A transcript that is
            // a verbatim excerpt of our own prompt is such an echo - drop it silently.
            if cleaned.count >= 12, prompt.contains(cleaned) {
                logger.debug("transcript discarded: verbatim prompt echo")
                phase = .idle
                statusText = "Ready"
                return
            }

            let raw = cleaned
            var final = cleaned
            var cleanupDuration = Duration.zero

            let rawWordCount = raw.split(whereSeparator: \.isWhitespace).count
            if preferences.cleanupLevel == .none {
                // Cleanup disabled; nothing to skip or run.
            } else if isLocal, preferences.localCleanupEngine == .rules {
                let cleanupStart = clock.now
                let tidied = FillerRemover.clean(raw)
                if !tidied.isEmpty {
                    final = tidied
                }
                cleanupDuration = clock.now - cleanupStart
            } else if rawWordCount < Self.minimumWordsForCleanup {
                logger.debug("cleanup skipped: transcript below word threshold")
            } else {
                let tone = AppToneProfile.profile(
                    forBundleID: pasteTargetApplication?.bundleIdentifier,
                    windowTitle: pasteTargetWindowTitle
                )
                statusText = "Polishing (\(tone.name))..."
                let bundleID = self.pasteTargetApplication?.bundleIdentifier ?? "nil"
                let windowTitle = self.pasteTargetWindowTitle ?? "nil"
                logger.debug("cleanup tone: \(tone.name, privacy: .public) for \(bundleID, privacy: .public) (window: \(windowTitle, privacy: .public))")
                let promptBuilder = CleanupPromptBuilder()
                let systemPrompt = isLocal
                    ? localCleanupSystemPrompt()
                    : promptBuilder.buildSystemPrompt(
                        level: preferences.cleanupLevel,
                        tone: tone,
                        vocabulary: dictionaryTerms,
                        rules: rules
                    )
                let cleanupStart = clock.now
                do {
                    let polished = TextCleaner.clean(
                        try await engine.chat.complete(
                            systemPrompt: systemPrompt,
                            userMessage: isLocal
                                ? promptBuilder.buildLocalCleanupUserMessage(transcript: raw)
                                : promptBuilder.buildCleanupUserMessage(transcript: raw),
                            model: OpenAIChatClient.cleanupModel,
                            apiKey: engine.apiKey
                        )
                    )
                    if polished.isEmpty {
                        // Keep the raw transcript.
                    } else if isLocal, !TranscriptChecks.cleanupKeptTheWords(raw: raw, cleaned: polished, level: preferences.cleanupLevel) {
                        // The small on-device model sometimes rewords or shortens the text
                        // although the level only allows tidying. The spoken words win.
                        logger.debug("cleanup discarded: output strayed from the spoken words")
                    } else {
                        final = DictionaryCorrector.apply(polished, terms: dictionaryTerms)
                    }
                } catch {
                    logger.error("AI cleanup failed: \(error.localizedDescription, privacy: .public)")
                    notifier.notify(title: "Wisper Clone", body: "AI cleanup failed — pasted raw transcript.")
                }
                cleanupDuration = clock.now - cleanupStart
            }

            // Appended after cleanup so the AI never rewrites, translates or "polishes"
            // the signature away. A one-shot override from the signature hotkey wins over
            // the per-app rule and is consumed here, whether or not it changed anything.
            let shouldAppendSignature = signatureOverride ?? SignatureAppender.shouldAppend(
                settings: preferences.signature,
                bundleID: pasteTargetApplication?.bundleIdentifier
            )
            signatureOverride = nil
            if shouldAppendSignature {
                final = SignatureAppender.append(
                    preferences.signature.trimmedText,
                    to: final,
                    separator: preferences.signature.separator
                )
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
            if recordingWasSilent {
                logger.debug("recording skipped: no audio above silence threshold")
                throw DictationError.emptyTranscript
            }
            let engine = try resolveEngine()

            // Activate the target app before capturing the selection, then capture it
            // after the hotkey release — synthesizing ⌘C while the hotkey modifiers are
            // still held would corrupt the copy shortcut.
            await frontmostApplicationTracker.activate(pasteTargetApplication)
            let selectedText = try await selectedTextCapturer.captureSelectedText()

            if let selectedText, wordCount(selectedText) > Self.maxSelectionWords {
                throw DictationError.selectionTooLong
            }

            let transcribeStart = clock.now
            let rawInstruction = try await engine.transcriber.transcribe(
                fileURL: fileURL,
                apiKey: engine.apiKey,
                model: preferences.transcriptionQuality.modelName,
                prompt: TranscriptionPromptBuilder().buildCommandInstructionPrompt(),
                language: preferences.languageMode.apiLanguageCode
            )
            let transcribeDuration = clock.now - transcribeStart

            let instruction = TextCleaner.clean(rawInstruction)
            guard !instruction.isEmpty else {
                throw DictationError.noInstruction
            }

            if let newRule = ruleAddition(in: instruction) {
                addRule(newRule)
                statusText = "Regel gespeichert"
                notifier.notify(title: "Wisper Clone", body: newRule)
                isCommandRecording = false
                phase = .idle
                return
            }

            statusText = "Running command..."
            let promptBuilder = CleanupPromptBuilder()
            let systemPrompt = promptBuilder.buildCommandSystemPrompt(
                hasSelection: selectedText != nil,
                appContext: commandAppContext(),
                rules: rules
            )
            let userMessage = promptBuilder.buildCommandUserMessage(
                instruction: instruction,
                selectedText: selectedText,
                lastTranscript: lastTranscript
            )

            let chatStart = clock.now
            let rawResult = try await engine.chat.complete(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                model: OpenAIChatClient.commandModel,
                apiKey: engine.apiKey
            )
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

    private struct ResolvedEngine {
        let transcriber: TranscriptionServicing
        let chat: ChatCompleting
        let apiKey: String
    }

    /// The Keychain is only read while the OpenAI engine is selected. A local-only setup
    /// never triggers a Keychain prompt, which would otherwise block the launch.
    private func refreshAPIKeyState() {
        guard preferences.engine == .openAI else { return }
        hasAPIKey = ((try? credentialStore.readAPIKey()) ?? nil)?.isEmpty == false
    }

    /// Picks the clients for the selected engine. The local engine needs no key.
    private func resolveEngine() throws -> ResolvedEngine {
        switch preferences.engine {
        case .local:
            return ResolvedEngine(transcriber: localTranscriptionClient, chat: localChatClient, apiKey: "")
        case .openAI:
            guard let apiKey = try credentialStore.readAPIKey(), !apiKey.isEmpty else {
                throw DictationError.missingAPIKey
            }
            return ResolvedEngine(transcriber: transcriptionClient, chat: chatClient, apiKey: apiKey)
        }
    }

    func setEngine(_ engine: ProcessingEngine) {
        preferences.engine = engine
        refreshAPIKeyState()
        prepareLocalModelsIfNeeded()
    }

    func setLocalSpeechModel(_ model: LocalSpeechModel) {
        guard preferences.localSpeechModel != model else { return }
        preferences.localSpeechModel = model
        prepareLocalModelsIfNeeded(reload: true)
    }

    func setBoostDictionaryTerms(_ enabled: Bool) {
        preferences.boostDictionaryTerms = enabled
        prepareLocalModelsIfNeeded(reload: true)
    }

    func setLocalCleanupEngine(_ engine: LocalCleanupEngine) {
        preferences.localCleanupEngine = engine
    }

    /// Loads the local speech model in the background so the first dictation does not
    /// wait for it. Safe to call repeatedly. `reload` applies a changed model or dictionary.
    func prepareLocalModelsIfNeeded(reload: Bool = false) {
        guard preferences.engine == .local,
              let preparing = localTranscriptionClient as? LocalModelPreparing else { return }
        guard reload || (localModelState != .loading && localModelState != .ready) else { return }
        localModelState = .loading
        localModelGeneration += 1
        let generation = localModelGeneration
        let model = preferences.localSpeechModel
        let vocabulary = preferences.boostDictionaryTerms ? dictionaryTerms : []
        Task {
            do {
                await preparing.configure(model: model, vocabulary: vocabulary)
                try await preparing.prepare()
                guard generation == localModelGeneration else { return }
                localModelState = .ready
            } catch {
                guard generation == localModelGeneration else { return }
                localModelState = .failed(error.localizedDescription)
                logger.error("local model load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        Task.detached(priority: .utility) {
            AppleIntelligenceChatClient.prewarm()
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
            isCommandRecording = false
        } catch {
            paster.copy(text)
            phase = .failed
            statusText = "Copied instead of pasted"
            notifier.notify(title: "Wisper Clone", body: error.localizedDescription)
            isCommandRecording = false
        }
    }

    private func fail(_ error: Error) {
        logger.error("dictation failed: \(error.localizedDescription, privacy: .public)")
        stopAudioLevelTimer()
        isHandsFreeActive = false
        isCommandRecording = false

        // Nothing usable was said: that is not worth an error. Go back to idle quietly.
        if let dictationError = error as? DictationError, dictationError == .emptyTranscript {
            phase = .idle
            statusText = "Ready"
            return
        }

        phase = .failed
        statusText = error.localizedDescription
        signal(.failed)
        notifier.notify(title: "Wisper Clone", body: error.localizedDescription)
        scheduleFailureReset()
    }

    /// A failure stays visible for a moment and then clears itself, so the Flow Bar does
    /// not keep showing an old error.
    private func scheduleFailureReset() {
        failureGeneration += 1
        let generation = failureGeneration
        let delay = failureDisplayDuration
        Task {
            try? await Task.sleep(for: delay)
            guard generation == failureGeneration, phase == .failed else { return }
            phase = .idle
            statusText = "Ready"
        }
    }

    private func signal(_ event: FeedbackEvent) {
        feedback.signal(event, sound: preferences.enableSounds, haptic: preferences.enableHaptics)
    }

    private func localCleanupSystemPrompt() -> String {
        CleanupPromptBuilder().buildLocalSystemPrompt(
            level: preferences.cleanupLevel,
            vocabulary: dictionaryTerms,
            rules: rules
        )
    }

    // Silently drops the current recording: no API call, no paste, no error surface.
    private func discardRecording(reason: String) {
        logger.debug("recording discarded: \(reason, privacy: .public)")
        audioRecorder.cancelRecording()
        isCommandRecording = false
        recordingMode = .dictation
        recordingStartedAt = nil
        phase = .idle
        statusText = "Ready"
    }

    private func startAudioLevelTimer() {
        recordingPeakLevel = 0
        recordingLevelSampleCount = 0
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
        let level = audioRecorder.currentAudioLevel
        recordingPeakLevel = max(recordingPeakLevel, level)
        recordingLevelSampleCount += 1
        samples.append(level)
        if samples.count > Self.maxAudioLevelSamples {
            samples.removeFirst(samples.count - Self.maxAudioLevelSamples)
        }
        audioLevels = samples
    }

    // True when level sampling ran and never rose above the silence threshold.
    private var recordingWasSilent: Bool {
        recordingLevelSampleCount > 0 && recordingPeakLevel < Self.silencePeakThreshold
    }

    private func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Deterministic prefix matching for "remember this as a rule" voice commands —
    /// intentionally not LLM-based so it never depends on network availability.
    private func ruleAddition(in instruction: String) -> String? {
        let lowered = instruction.lowercased()
        guard let prefix = Self.ruleTriggerPrefixes.first(where: { lowered.hasPrefix($0) }) else {
            return nil
        }

        let startIndex = instruction.index(instruction.startIndex, offsetBy: prefix.count)
        var rest = String(instruction[startIndex...])
        while let first = rest.first, first.isWhitespace || ":,;.-".contains(first) {
            rest.removeFirst()
        }

        guard !rest.isEmpty else { return nil }
        return rest
    }

    private func commandAppContext() -> String? {
        guard let appName = pasteTargetApplication?.localizedName else { return nil }
        if let windowTitle = pasteTargetWindowTitle, !windowTitle.isEmpty {
            return "Context: the result will be inserted into \(appName) (window: \"\(windowTitle)\"). Match the conventions of that context."
        }
        return "Context: the result will be inserted into \(appName). Match the conventions of that context."
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
