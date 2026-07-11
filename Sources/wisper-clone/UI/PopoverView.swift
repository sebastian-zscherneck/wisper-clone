import SwiftUI

struct PopoverView: View {
    @ObservedObject var coordinator: DictationCoordinator
    @State private var apiKeyInput = ""
    @State private var dictionaryInput = ""
    @State private var ruleInput = ""
    @State private var isRecordingIndicatorExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                setupSection
                controlsSection
                audioSection
                dictionarySection
                rulesSection
                lastTranscriptSection
                historySection
                footer
            }
            .padding(.top, 22)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 420, height: 780)
        .onAppear {
            coordinator.refreshInputDevices()
            updateRecordingIndicatorAnimation()
        }
        .onDisappear {
            coordinator.cancelHotkeyCapture()
        }
        .onChange(of: coordinator.phase) { _, _ in
            updateRecordingIndicatorAnimation()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Wisper Clone")
                    .font(.headline)
                Text(coordinator.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if coordinator.phase == .recording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(recordingIndicatorColor)
                        .frame(width: 7, height: 7)
                        .scaleEffect(isRecordingIndicatorExpanded ? 1.35 : 0.85)
                        .opacity(isRecordingIndicatorExpanded ? 0.55 : 1)
                    Text("REC")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(recordingIndicatorColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(recordingIndicatorColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(coordinator.hasAPIKey ? "API key saved" : "API key required", systemImage: coordinator.hasAPIKey ? "key.fill" : "key")
                    .font(.subheadline)
                Spacer()
                if coordinator.hasAPIKey {
                    Button("Remove") {
                        coordinator.clearAPIKey()
                    }
                    .controlSize(.small)
                }
            }

            HStack {
                SecureField("OpenAI API key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                Button {
                    coordinator.saveAPIKey(apiKeyInput)
                    apiKeyInput = ""
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save API key")
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Hold shortcuts")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Label(
                        coordinator.isGlobalShortcutReady ? "Global ready" : "Needs Input",
                        systemImage: coordinator.isGlobalShortcutReady ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(coordinator.isGlobalShortcutReady ? .green : .orange)
                }

                ForEach(Array(coordinator.preferences.hotkeys.enumerated()), id: \.element) { index, binding in
                    HStack {
                        hotkeyRecorderField(
                            display: binding.displayName,
                            target: .dictation(index: index)
                        )
                        Button {
                            coordinator.removeDictationHotkey(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Remove hotkey")
                        .disabled(coordinator.preferences.hotkeys.count <= 1)
                    }
                }

                Button {
                    coordinator.beginHotkeyCapture(for: .dictation(index: nil))
                } label: {
                    Label("Add hotkey", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(coordinator.hotkeyCaptureTarget != nil)
            }

            HStack {
                Text("Command hotkey")
                Spacer()
                hotkeyRecorderField(
                    display: coordinator.preferences.commandHotkey?.displayName ?? "Off",
                    target: .command
                )
                if coordinator.preferences.commandHotkey != nil {
                    Button {
                        coordinator.setCommandHotkey(nil)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Turn off command hotkey")
                }
            }

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { coordinator.preferences.launchAtLogin },
                    set: { coordinator.setLaunchAtLogin($0) }
                )
            )

            Toggle(
                "Show Flow Bar",
                isOn: Binding(
                    get: { coordinator.preferences.showFlowBar },
                    set: { coordinator.preferences.showFlowBar = $0 }
                )
            )

            HStack {
                Button {
                    coordinator.beginRecording()
                } label: {
                    Label("Record", systemImage: "mic.fill")
                }
                .disabled(coordinator.phase == .recording || coordinator.phase == .transcribing)

                Button {
                    coordinator.finishRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(coordinator.phase != .recording)

                Button {
                    coordinator.cancelRecording()
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Cancel recording")
                .disabled(coordinator.phase != .recording)
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audio")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    coordinator.refreshInputDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh input devices")
            }

            Picker(
                "Microphone",
                selection: Binding(
                    get: { coordinator.preferences.selectedInputDeviceID ?? "" },
                    set: { coordinator.setSelectedInputDeviceID($0.isEmpty ? nil : $0) }
                )
            ) {
                Text("Automatic")
                    .tag("")
                ForEach(coordinator.inputDevices) { device in
                    Text(device.displayName)
                        .tag(device.id)
                }
            }

            Picker(
                "Language",
                selection: Binding(
                    get: { coordinator.preferences.languageMode },
                    set: { coordinator.setLanguageMode($0) }
                )
            ) {
                ForEach(TranscriptionLanguageMode.allCases) { mode in
                    Text(mode.displayName)
                        .tag(mode)
                }
            }

            if selectedInputDevice?.isBluetoothLike == true {
                Label("Bluetooth microphones can reduce AirPods music quality.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Picker(
                "Transcription",
                selection: Binding(
                    get: { coordinator.preferences.transcriptionQuality },
                    set: { coordinator.setTranscriptionQuality($0) }
                )
            ) {
                ForEach(TranscriptionQuality.allCases) { quality in
                    Text(quality.displayName)
                        .tag(quality)
                }
            }
            Text("Accurate: better German + custom vocabulary. Fast: lower latency.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "AI cleanup",
                selection: Binding(
                    get: { coordinator.preferences.cleanupLevel },
                    set: { coordinator.setCleanupLevel($0) }
                )
            ) {
                ForEach(CleanupLevel.allCases) { level in
                    Text(level.displayName)
                        .tag(level)
                }
            }
            Text("Off pastes the raw transcript. Higher levels rewrite more.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lastTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Last transcript")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    coordinator.retryLastPaste()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .help("Paste again")
                .disabled(coordinator.lastTranscript.isEmpty)

                Button {
                    coordinator.copyLastTranscript()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
                .disabled(coordinator.lastTranscript.isEmpty)

                if let latestEntry = coordinator.history.first, latestEntry.wasEdited {
                    Button {
                        coordinator.pasteRaw(latestEntry)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .help("Undo AI edit")
                }
            }

            ScrollView {
                Text(coordinator.lastTranscript.isEmpty ? "No transcript yet." : coordinator.lastTranscript)
                    .font(.body)
                    .foregroundStyle(coordinator.lastTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: 92)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var dictionarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dictionary")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                TextField("Add word or phrase", text: $dictionaryInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDictionaryInput)

                Button {
                    addDictionaryInput()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add dictionary term")
                .disabled(dictionaryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(coordinator.dictionaryTerms, id: \.self) { term in
                        HStack(spacing: 4) {
                            Text(term)
                                .lineLimit(1)
                            Button {
                                coordinator.removeDictionaryTerm(term)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(term)")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Rules")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                TextField("Add a rule (e.g. never use exclamation marks)", text: $ruleInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addRuleInput)

                Button {
                    addRuleInput()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add rule")
                .disabled(ruleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(coordinator.rules, id: \.self) { rule in
                        HStack(spacing: 4) {
                            Text(rule)
                                .lineLimit(1)
                            Button {
                                coordinator.removeRule(rule)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(rule)")
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Session history")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    coordinator.clearSessionHistory()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Clear session history")
                .disabled(coordinator.history.isEmpty)
            }

            List(coordinator.history) { entry in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.text)
                            .lineLimit(2)
                        Text(entry.createdAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        coordinator.removeHistoryEntry(entry.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Remove entry")
                }
                .padding(.vertical, 2)
                .contextMenu {
                    if entry.wasEdited {
                        Button("Copy raw") {
                            coordinator.copyRaw(entry)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .frame(height: 120)
        }
    }

    private var footer: some View {
        HStack {
            Button("Mic Settings") {
                coordinator.openMicrophoneSettings()
            }
            Button("Input") {
                coordinator.openInputMonitoringSettings()
            }
            Button("Accessibility") {
                coordinator.openAccessibilitySettings()
            }
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .font(.caption)
    }

    private func hotkeyRecorderField(
        display: String,
        target: DictationCoordinator.HotkeyCaptureTarget
    ) -> some View {
        let isRecording = coordinator.hotkeyCaptureTarget == target
        return Button {
            if isRecording {
                coordinator.cancelHotkeyCapture()
            } else {
                coordinator.beginHotkeyCapture(for: target)
            }
        } label: {
            Text(isRecording ? "Press shortcut…" : display)
                .font(.callout.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 110)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : Color.secondary.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press the keys or mouse button to assign (Esc cancels)" : "Click, then press your shortcut")
    }

    private func addDictionaryInput() {
        coordinator.addDictionaryTerm(dictionaryInput)
        dictionaryInput = ""
    }

    private func addRuleInput() {
        coordinator.addRule(ruleInput)
        ruleInput = ""
    }

    private func updateRecordingIndicatorAnimation() {
        guard coordinator.phase == .recording else {
            isRecordingIndicatorExpanded = false
            return
        }

        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
            isRecordingIndicatorExpanded = true
        }
    }

    private var selectedInputDevice: AudioInputDevice? {
        guard let selectedInputDeviceID = coordinator.preferences.selectedInputDeviceID else {
            return nil
        }
        return coordinator.inputDevices.first { $0.id == selectedInputDeviceID }
    }

    private var iconName: String {
        switch coordinator.phase {
        case .idle:
            return "waveform.circle"
        case .recording:
            return "mic.circle.fill"
        case .transcribing:
            return "arrow.triangle.2.circlepath.circle"
        case .pasting:
            return "arrow.down.doc"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch coordinator.phase {
        case .idle:
            return .accentColor
        case .recording:
            return recordingIndicatorColor
        case .transcribing, .pasting:
            return .orange
        case .failed:
            return .red
        }
    }

    private var recordingIndicatorColor: Color {
        coordinator.isCommandRecording ? .indigo : Color(red: 0.2, green: 0.78, blue: 0.45)
    }
}
