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
        Section("On-Device Models") {
            LabeledContent("Speech recognition") {
                StatusLabel(text: speechModelText, state: speechModelIndicator)
            }
            LabeledContent("Language model") {
                StatusLabel(
                    text: languageModelReason ?? "Apple Intelligence · ready",
                    state: languageModelReason == nil ? .ok : .warning
                )
            }
            if case .failed = coordinator.localModelState {
                Button("Try Again") {
                    coordinator.prepareLocalModelsIfNeeded()
                }
            }
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
            return "Parakeet v3 · not loaded"
        case .loading:
            return "Parakeet v3 · loading…"
        case .ready:
            return "Parakeet v3 · ready"
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
