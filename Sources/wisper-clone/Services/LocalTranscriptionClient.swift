import FluidAudio
import Foundation

/// Implemented by transcription clients that need to load a model before the first use.
protocol LocalModelPreparing: Sendable {
    func prepare() async throws
}

/// On-device speech-to-text with Parakeet TDT v3 via FluidAudio. The model (about 600 MB)
/// is downloaded once into ~/Library/Application Support/FluidAudio and then runs on the
/// Neural Engine. No audio leaves the Mac.
///
/// Parakeet detects the spoken language itself and takes no prompt, so `apiKey`, `model`,
/// `prompt` and `language` from the shared protocol are ignored here.
actor LocalTranscriptionClient: TranscriptionServicing, LocalModelPreparing {
    private var manager: AsrManager?
    private var decoderLayers = 0
    private var loadTask: Task<Void, Error>?

    func prepare() async throws {
        if manager != nil { return }
        if let loadTask {
            try await loadTask.value
            return
        }
        let task = Task {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = AsrManager(models: models)
            self.decoderLayers = await manager.decoderLayerCount
            self.manager = manager
        }
        loadTask = task
        do {
            try await task.value
        } catch {
            loadTask = nil
            throw DictationError.transcriptionFailed(
                "The local speech model could not be loaded: \(error.localizedDescription)"
            )
        }
    }

    func transcribe(fileURL: URL, apiKey: String, model: String, prompt: String?, language: String?) async throws -> String {
        try await prepare()
        guard let manager else {
            throw DictationError.transcriptionFailed("The local speech model is not loaded.")
        }
        do {
            var state = try TdtDecoderState(decoderLayers: decoderLayers)
            let result = try await manager.transcribe(fileURL, decoderState: &state)
            return result.text
        } catch {
            throw DictationError.transcriptionFailed("Local transcription failed: \(error.localizedDescription)")
        }
    }
}
