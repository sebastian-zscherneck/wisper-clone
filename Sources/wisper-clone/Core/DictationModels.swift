import Foundation

enum DictationPhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case pasting
    case failed
}

struct TranscriptEntry: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let text: String
    let rawText: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, rawText: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.rawText = rawText ?? text
        self.createdAt = createdAt
    }

    var wasEdited: Bool { rawText != text }
}

struct AppPreferences: Equatable, Sendable {
    var hotkeys: Set<Hotkey> = [.fn, .mouse5]
    var launchAtLogin: Bool = false
    var languageMode: TranscriptionLanguageMode = .bilingual
    var selectedInputDeviceID: String? = nil
    var cleanupLevel: CleanupLevel = .none
}

struct AudioInputDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isBluetoothLike: Bool

    var displayName: String {
        isBluetoothLike ? "\(name) (Bluetooth)" : name
    }
}

enum TranscriptionLanguageMode: String, CaseIterable, Identifiable, Sendable {
    case bilingual
    case german
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bilingual:
            return "Deutsch + English"
        case .german:
            return "Deutsch"
        case .english:
            return "English"
        }
    }

    var apiLanguageCode: String? {
        switch self {
        case .bilingual:
            return nil
        case .german:
            return "de"
        case .english:
            return "en"
        }
    }
}

enum CleanupLevel: String, CaseIterable, Identifiable, Sendable {
    case none
    case light
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "Off"
        case .light:
            return "Light"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

enum Hotkey: String, CaseIterable, Identifiable, Sendable {
    case fn
    case mouse5
    case optionSpace
    case controlSpace

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn:
            return "Fn hold"
        case .mouse5:
            return "Mouse 5 hold"
        case .optionSpace:
            return "Option+Space hold"
        case .controlSpace:
            return "Control+Space hold"
        }
    }
}

enum DictationError: LocalizedError, Equatable {
    case missingAPIKey
    case microphoneDenied
    case accessibilityDenied
    case recordingUnavailable
    case emptyTranscript
    case pasteFailed
    case transcriptionFailed(String)
    case chatCompletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your OpenAI API key before recording."
        case .microphoneDenied:
            return "Microphone permission is required to record audio."
        case .accessibilityDenied:
            return "Accessibility permission is required to paste into other apps."
        case .recordingUnavailable:
            return "Could not start audio recording."
        case .emptyTranscript:
            return "The transcription was empty."
        case .pasteFailed:
            return "The text was copied, but automatic paste failed."
        case .transcriptionFailed(let message):
            return message
        case .chatCompletionFailed(let message):
            return "AI processing failed: \(message)"
        }
    }
}
