import FluidAudio
import Foundation
import os

/// Implemented by transcription clients that need to load a model before the first use.
protocol LocalModelPreparing: Sendable {
    func prepare() async throws
    /// Selects the speech model and the terms to boost. Takes effect with the next
    /// `prepare()` or transcription.
    func configure(model: LocalSpeechModel, vocabulary: [String]) async
}

/// On-device speech-to-text with a Parakeet model via FluidAudio. The model (about 600 MB)
/// is downloaded once into ~/Library/Application Support/FluidAudio and then runs on the
/// Neural Engine. No audio leaves the Mac.
///
/// Parakeet detects the spoken language itself and takes no prompt, so `apiKey`, `model`,
/// `prompt` and `language` from the shared protocol are ignored here. Unknown names and
/// jargon are handled by vocabulary boosting instead: a small second model (Parakeet CTC,
/// about 100 MB) scores the dictionary terms against the audio, and a term replaces the
/// transcribed word only where it fits the sound better.
actor LocalTranscriptionClient: TranscriptionServicing, LocalModelPreparing {
    private struct Booster {
        let terms: [String]
        let vocabulary: CustomVocabularyContext
        let spotter: CtcKeywordSpotter
        let rescorer: VocabularyRescorer
    }

    private let logger = Logger(subsystem: "com.wisper-clone", category: "LocalTranscriptionClient")
    private let audioConverter = AudioConverter()

    private var selectedModel: LocalSpeechModel = .parakeetUltra
    private var vocabularyTerms: [String] = []

    private var manager: AsrManager?
    private var loadedModel: LocalSpeechModel?
    private var decoderLayers = 0
    private var loadTask: (model: LocalSpeechModel, task: Task<Void, Error>)?

    private var ctcModels: CtcModels?
    private var booster: Booster?

    func configure(model: LocalSpeechModel, vocabulary: [String]) {
        selectedModel = model
        vocabularyTerms = vocabulary
    }

    func prepare() async throws {
        try await loadSpeechModel()
        // Boosting is an extra: without it the dictation still works.
        await loadBoosterIfNeeded()
    }

    func transcribe(fileURL: URL, apiKey: String, model: String, prompt: String?, language: String?) async throws -> String {
        try await loadSpeechModel()
        guard let manager else {
            throw DictationError.transcriptionFailed("The local speech model is not loaded.")
        }
        let samples: [Float]
        let result: ASRResult
        do {
            samples = try audioConverter.resampleAudioFile(fileURL)
            var state = TdtDecoderState.make(decoderLayers: decoderLayers)
            result = try await manager.transcribe(samples, decoderState: &state)
        } catch {
            throw DictationError.transcriptionFailed("Local transcription failed: \(error.localizedDescription)")
        }
        return await boosted(result, samples: samples)
    }

    // MARK: - Speech model

    private func loadSpeechModel() async throws {
        let wanted = selectedModel
        if manager != nil, loadedModel == wanted { return }

        let task: Task<Void, Error>
        if let loadTask, loadTask.model == wanted {
            task = loadTask.task
        } else {
            task = Task {
                let models = try await AsrModels.downloadAndLoad(version: wanted.fluidAudioVersion)
                let manager = AsrManager(models: models)
                let layers = await manager.decoderLayerCount
                self.install(manager, layers: layers, for: wanted)
            }
            loadTask = (wanted, task)
        }

        do {
            try await task.value
        } catch {
            if loadTask?.model == wanted {
                loadTask = nil
            }
            throw DictationError.transcriptionFailed(
                "The local speech model could not be loaded: \(error.localizedDescription)"
            )
        }
        // The selection changed while this model was loading: load the new one.
        if selectedModel != wanted {
            try await loadSpeechModel()
        }
    }

    private func install(_ manager: AsrManager, layers: Int, for model: LocalSpeechModel) {
        self.manager = manager
        decoderLayers = layers
        loadedModel = model
        if loadTask?.model == model {
            loadTask = nil
        }
    }

    // MARK: - Vocabulary boosting

    private func boosted(_ result: ASRResult, samples: [Float]) async -> String {
        guard let tokenTimings = result.tokenTimings, !tokenTimings.isEmpty,
              let booster = await loadBoosterIfNeeded() else {
            return result.text
        }
        do {
            let spotted = try await booster.spotter.spotKeywordsWithLogProbs(
                audioSamples: samples,
                customVocabulary: booster.vocabulary,
                minScore: nil
            )
            guard !spotted.logProbs.isEmpty else { return result.text }
            let tuning = ContextBiasingConstants.rescorerConfig(forVocabSize: booster.vocabulary.terms.count)
            let output = booster.rescorer.ctcTokenRescore(
                transcript: result.text,
                tokenTimings: tokenTimings,
                logProbs: spotted.logProbs,
                frameDuration: spotted.frameDuration,
                cbw: tuning.cbw,
                marginSeconds: ContextBiasingConstants.defaultMarginSeconds,
                minSimilarity: tuning.minSimilarity
            )
            return output.wasModified ? output.text : result.text
        } catch {
            logger.error("vocabulary boosting failed: \(error.localizedDescription, privacy: .public)")
            return result.text
        }
    }

    @discardableResult
    private func loadBoosterIfNeeded() async -> Booster? {
        let terms = vocabularyTerms
        guard !terms.isEmpty else {
            booster = nil
            return nil
        }
        if let booster, booster.terms == terms { return booster }

        do {
            let models: CtcModels
            if let ctcModels {
                models = ctcModels
            } else {
                models = try await CtcModels.downloadAndLoad(variant: .ctc110m)
                ctcModels = models
            }
            let modelDirectory = CtcModels.defaultCacheDirectory(for: models.variant)
            let tokenizer = try await CtcTokenizer.load(from: modelDirectory)
            let vocabularyTermsWithTokens = terms.compactMap { term -> CustomVocabularyTerm? in
                let tokenIds = tokenizer.encode(term)
                guard !tokenIds.isEmpty else { return nil }
                return CustomVocabularyTerm(text: term, ctcTokenIds: tokenIds)
            }
            guard !vocabularyTermsWithTokens.isEmpty else { return nil }
            let vocabulary = CustomVocabularyContext(terms: vocabularyTermsWithTokens)
            let spotter = CtcKeywordSpotter(models: models, blankId: models.vocabulary.count)
            // Without the spotter rescue a term only replaces a word it resembles. With it,
            // short dictionary words overwrote unrelated speech ("baue ich" became "Launch").
            let rescorer = try await VocabularyRescorer.create(
                spotter: spotter,
                vocabulary: vocabulary,
                config: VocabularyRescorer.Config(spotterRescueEnabled: false),
                ctcModelDirectory: modelDirectory
            )
            let loaded = Booster(terms: terms, vocabulary: vocabulary, spotter: spotter, rescorer: rescorer)
            // Only keep it if the dictionary did not change while it was being built.
            if vocabularyTerms == terms {
                booster = loaded
            }
            return loaded
        } catch {
            logger.error("vocabulary booster could not be loaded: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

private extension LocalSpeechModel {
    var fluidAudioVersion: AsrModelVersion {
        switch self {
        case .parakeetUltra:
            return .ultra
        case .parakeetV3:
            return .v3
        }
    }
}
