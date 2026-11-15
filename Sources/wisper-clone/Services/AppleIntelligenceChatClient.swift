import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Text cleanup and Command Mode on Apple's on-device language model (macOS 26 with
/// Apple Intelligence turned on). `model` and `apiKey` from the shared protocol are ignored.
struct AppleIntelligenceChatClient: ChatCompleting, ChatPrewarming, Sendable {
    private static let warmSessions = WarmSessionSlot()

    /// `nil` when the on-device model can be used, otherwise a sentence that says why not.
    static func unavailabilityReason() -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else {
            return "The on-device language model needs macOS 26 or newer."
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This Mac does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to use AI cleanup."
        case .unavailable(.modelNotReady):
            return "The on-device language model is still downloading."
        case .unavailable:
            return "The on-device language model is not available."
        }
        #else
        return "The on-device language model needs macOS 26 or newer."
        #endif
    }

    /// Loads the model into memory ahead of the first request. Best effort.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), unavailabilityReason() == nil {
            LanguageModelSession().prewarm()
        }
        #endif
    }

    /// Creates the session for `systemPrompt` ahead of time and loads the prompt into the
    /// model. `complete` picks that session up if it is asked for the same prompt.
    func prewarm(systemPrompt: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), Self.unavailabilityReason() == nil {
            let session = LanguageModelSession(instructions: systemPrompt)
            session.prewarm()
            Self.warmSessions.store(session, for: systemPrompt)
        }
        #endif
    }

    func complete(systemPrompt: String, userMessage: String, model: String, apiKey: String) async throws -> String {
        if let reason = Self.unavailabilityReason() {
            throw DictationError.chatCompletionFailed(reason)
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            // A session keeps its conversation, so each one answers exactly one request.
            let session = (Self.warmSessions.take(for: systemPrompt) as? LanguageModelSession)
                ?? LanguageModelSession(instructions: systemPrompt)
            do {
                let response = try await session.respond(
                    to: userMessage,
                    options: GenerationOptions(sampling: .greedy)
                )
                let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw DictationError.chatCompletionFailed("Empty response")
                }
                return trimmed
            } catch let error as DictationError {
                throw error
            } catch {
                throw DictationError.chatCompletionFailed(error.localizedDescription)
            }
        }
        #endif
        throw DictationError.chatCompletionFailed("The on-device language model is not available.")
    }
}

/// Implemented by chat clients that can prepare a request before its text is known.
protocol ChatPrewarming: Sendable {
    func prewarm(systemPrompt: String)
}

/// Holds the one prewarmed session between "recording started" and "transcript ready".
private final class WarmSessionSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var systemPrompt: String?
    private var session: AnyObject?

    func store(_ session: AnyObject, for systemPrompt: String) {
        lock.withLock {
            self.systemPrompt = systemPrompt
            self.session = session
        }
    }

    func take(for systemPrompt: String) -> AnyObject? {
        lock.withLock {
            guard self.systemPrompt == systemPrompt else { return nil }
            defer {
                self.systemPrompt = nil
                self.session = nil
            }
            return session
        }
    }
}
