import SwiftUI

struct ModelsSettingsPane: View {
    @ObservedObject var coordinator: DictationCoordinator
    @State private var apiKeyInput = ""

    var body: some View {
        Form {
            Section {
                Picker(
                    "Processing",
                    selection: Binding(
                        get: { coordinator.preferences.engine },
                        set: { coordinator.setEngine($0) }
                    )
                ) {
                    ForEach(ProcessingEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
            } footer: {
                switch coordinator.preferences.engine {
                case .local:
                    Text("Speech and text are processed on this Mac. Nothing is sent to a server.")
                case .openAI:
                    Text("Audio and text are sent to OpenAI with your own API key.")
                }
            }

            switch coordinator.preferences.engine {
            case .local:
                localSection
            case .openAI:
                openAISection
            }

            cleanupSection
        }
    }

    private var localSection: some View {
        Section {
            Picker(
                "Speech model",
                selection: Binding(
                    get: { coordinator.preferences.localSpeechModel },
                    set: { coordinator.setLocalSpeechModel($0) }
                )
            ) {
                ForEach(LocalSpeechModel.allCases) { model in
                    Text(model.displayName).tag(model)
                }
            }
            LabeledContent("Status") {
                StatusLabel(text: speechModelText, state: speechModelIndicator)
            }
            if case .failed = coordinator.localModelState {
                Button("Try Again") {
                    coordinator.prepareLocalModelsIfNeeded()
                }
            }
            Toggle(
                "Boost dictionary words",
                isOn: Binding(
                    get: { coordinator.preferences.boostDictionaryTerms },
                    set: { coordinator.setBoostDictionaryTerms($0) }
                )
            )
            Picker(
                "Text cleanup",
                selection: Binding(
                    get: { coordinator.preferences.localCleanupEngine },
                    set: { coordinator.setLocalCleanupEngine($0) }
                )
            ) {
                ForEach(LocalCleanupEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            if coordinator.preferences.localCleanupEngine == .appleIntelligence {
                LabeledContent("Language model") {
                    StatusLabel(
                        text: languageModelReason ?? "Apple Intelligence · ready",
                        state: languageModelReason == nil ? .ok : .warning
                    )
                }
            }
        } header: {
            Text("On-Device Models")
        } footer: {
            Text(localFooterText)
        }
    }

    private var localFooterText: String {
        let boosting = "Boosting checks the words from your dictionary against the audio, so names and jargon are spelled right. A new speech model is downloaded once (about 600 MB)."
        switch coordinator.preferences.localCleanupEngine {
        case .appleIntelligence:
            return boosting + " Apple Intelligence supports every cleanup level, but takes several seconds on long dictations."
        case .rules:
            return boosting + " Fast cleanup removes filler sounds and repeated words without a language model, so long dictations paste right away. Medium and High behave like Light."
        }
    }

    private var openAISection: some View {
        Section("OpenAI") {
            LabeledContent("API key") {
                HStack {
                    if coordinator.hasAPIKey {
                        StatusLabel(text: "Saved in Keychain", state: .ok)
                        Button("Remove") {
                            coordinator.clearAPIKey()
                        }
                    } else {
                        SecureField("sk-…", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                            .onSubmit(saveAPIKey)
                        Button("Save", action: saveAPIKey)
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            Picker(
                "Transcription model",
                selection: Binding(
                    get: { coordinator.preferences.transcriptionQuality },
                    set: { coordinator.setTranscriptionQuality($0) }
                )
            ) {
                ForEach(TranscriptionQuality.allCases) { quality in
                    Text(quality.displayName).tag(quality)
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
                    Text(mode.displayName).tag(mode)
                }
            }
        }
    }

    private var cleanupSection: some View {
        Section {
            Picker(
                "AI cleanup",
                selection: Binding(
                    get: { coordinator.preferences.cleanupLevel },
                    set: { coordinator.setCleanupLevel($0) }
                )
            ) {
                ForEach(CleanupLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
        } header: {
            Text("Formatting")
        } footer: {
            Text("Off pastes the raw transcript. Higher levels rewrite more.")
        }
    }

    private var languageModelReason: String? {
        AppleIntelligenceChatClient.unavailabilityReason()
    }

    private var speechModelText: String {
        switch coordinator.localModelState {
        case .notLoaded:
            return "\(coordinator.preferences.localSpeechModel.shortName) · not loaded"
        case .loading:
            return "\(coordinator.preferences.localSpeechModel.shortName) · loading…"
        case .ready:
            return "\(coordinator.preferences.localSpeechModel.shortName) · ready"
        case .failed(let message):
            return message
        }
    }

    private var speechModelIndicator: StatusLabel.State {
        switch coordinator.localModelState {
        case .ready:
            return .ok
        case .failed:
            return .error
        case .notLoaded, .loading:
            return .pending
        }
    }

    private func saveAPIKey() {
        coordinator.saveAPIKey(apiKeyInput)
        apiKeyInput = ""
    }
}

/// Small coloured dot with a status text, used for model and permission rows.
struct StatusLabel: View {
    enum State {
        case ok, pending, warning, error
    }

    let text: String
    let state: State

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var color: Color {
        switch state {
        case .ok: return .green
        case .pending: return .gray
        case .warning: return .orange
        case .error: return .red
        }
    }
}
