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
    var hotkeys: [HotkeyBinding] = [.fn, .mouse5]
    var launchAtLogin: Bool = false
    var languageMode: TranscriptionLanguageMode = .bilingual
    var selectedInputDeviceID: String? = nil
    var cleanupLevel: CleanupLevel = .none
    var commandHotkey: HotkeyBinding? = nil
    var showFlowBar: Bool = true
    var transcriptionQuality: TranscriptionQuality = .accurate
    var signature = SignatureSettings()
    var signatureHotkey: HotkeyBinding? = nil
}

/// One app the signature applies to. The name is stored alongside the bundle ID so the
/// settings list can label the row even while the app isn't running.
struct SignatureApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }

    /// Pre-filled so turning the feature on is a single click. Chat apps only —
    /// a signature under every email or commit message is rarely wanted.
    static let defaults: [SignatureApp] = [
        SignatureApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
        SignatureApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp")
    ]

    /// Offered in the "Add app" menu on top of the currently running apps, so an app
    /// can be configured while it is closed.
    static let suggestions: [SignatureApp] = defaults + [
        SignatureApp(bundleID: "com.hnc.discord", name: "Discord"),
        SignatureApp(bundleID: "ru.keepcoder.telegram", name: "Telegram"),
        SignatureApp(bundleID: "com.apple.MobileSMS", name: "Messages"),
        SignatureApp(bundleID: "com.microsoft.teams2", name: "Microsoft Teams"),
        SignatureApp(bundleID: "notion.id", name: "Notion")
    ]
}

/// How the signature is joined to the dictated text.
enum SignatureSeparator: String, Codable, CaseIterable, Identifiable, Sendable {
    case space
    case newline
    case blankLine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .space:
            return "Same line"
        case .newline:
            return "New line"
        case .blankLine:
            return "Blank line"
        }
    }

    var text: String {
        switch self {
        case .space:
            return " "
        case .newline:
            return "\n"
        case .blankLine:
            return "\n\n"
        }
    }
}

struct SignatureSettings: Codable, Equatable, Sendable {
    var isAutoAppendEnabled: Bool = false
    var text: String = "Made with WisprFlow"
    var separator: SignatureSeparator = .newline
    var apps: [SignatureApp] = SignatureApp.defaults

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init() {}

    /// Decodes field by field so a stored blob written by an older build — or a future one
    /// missing a key we add later — falls back to the default instead of failing the whole
    /// decode and silently resetting every signature setting.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var defaults = SignatureSettings()
        defaults.isAutoAppendEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .isAutoAppendEnabled) ?? defaults.isAutoAppendEnabled
        defaults.text = try container.decodeIfPresent(String.self, forKey: .text) ?? defaults.text
        defaults.separator =
            try container.decodeIfPresent(SignatureSeparator.self, forKey: .separator) ?? defaults.separator
        defaults.apps = try container.decodeIfPresent([SignatureApp].self, forKey: .apps) ?? defaults.apps
        self = defaults
    }
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

enum TranscriptionQuality: String, CaseIterable, Identifiable, Sendable {
    case accurate
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accurate:
            return "Accurate"
        case .fast:
            return "Fast"
        }
    }

    var modelName: String {
        switch self {
        case .accurate:
            return "gpt-4o-transcribe"
        case .fast:
            return "gpt-4o-mini-transcribe"
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

enum DictationError: LocalizedError, Equatable {
    case missingAPIKey
    case microphoneDenied
    case accessibilityDenied
    case recordingUnavailable
    case emptyTranscript
    case pasteFailed
    case transcriptionFailed(String)
    case chatCompletionFailed(String)
    case noInstruction
    case selectionTooLong

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
        case .noInstruction:
            return "No spoken instruction was recognized."
        case .selectionTooLong:
            return "Selection is too long to edit — try again with under 1,000 words."
        }
    }
}
