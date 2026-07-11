import Foundation

protocol AppPreferencesStoring {
    func loadPreferences() -> AppPreferences
    func savePreferences(_ preferences: AppPreferences)
}

struct UserDefaultsAppPreferencesStore: AppPreferencesStoring {
    private let defaults: UserDefaults
    private let hotkeyBindingsKey = "preferences.hotkeyBindings"
    private let commandBindingKey = "preferences.commandBinding"
    // Legacy keys from the removed `Hotkey` enum; read once for migration.
    private let hotkeysKey = "preferences.hotkeys"
    private let languageModeKey = "preferences.languageMode"
    private let selectedInputDeviceIDKey = "preferences.selectedInputDeviceID"
    private let cleanupLevelKey = "preferences.cleanupLevel"
    private let commandHotkeyKey = "preferences.commandHotkey"
    private let showFlowBarKey = "preferences.showFlowBar"
    private let transcriptionQualityKey = "preferences.transcriptionQuality"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPreferences() -> AppPreferences {
        var preferences = AppPreferences()

        if let data = defaults.data(forKey: hotkeyBindingsKey),
           let bindings = try? JSONDecoder().decode([HotkeyBinding].self, from: data),
           !bindings.isEmpty {
            preferences.hotkeys = bindings
        } else if let rawHotkeys = defaults.stringArray(forKey: hotkeysKey) {
            let bindings = rawHotkeys.compactMap(HotkeyBinding.init(legacyHotkeyRawValue:))
            if !bindings.isEmpty {
                preferences.hotkeys = bindings
            }
        }

        if let rawLanguageMode = defaults.string(forKey: languageModeKey),
           let languageMode = TranscriptionLanguageMode(rawValue: rawLanguageMode) {
            preferences.languageMode = languageMode
        }

        preferences.selectedInputDeviceID = defaults.string(forKey: selectedInputDeviceIDKey)

        if let rawCleanupLevel = defaults.string(forKey: cleanupLevelKey),
           let cleanupLevel = CleanupLevel(rawValue: rawCleanupLevel) {
            preferences.cleanupLevel = cleanupLevel
        }

        if let data = defaults.data(forKey: commandBindingKey) {
            preferences.commandHotkey = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
        } else if let rawCommandHotkey = defaults.string(forKey: commandHotkeyKey) {
            preferences.commandHotkey = HotkeyBinding(legacyHotkeyRawValue: rawCommandHotkey)
        }

        if defaults.object(forKey: showFlowBarKey) != nil {
            preferences.showFlowBar = defaults.bool(forKey: showFlowBarKey)
        }

        if let rawTranscriptionQuality = defaults.string(forKey: transcriptionQualityKey),
           let transcriptionQuality = TranscriptionQuality(rawValue: rawTranscriptionQuality) {
            preferences.transcriptionQuality = transcriptionQuality
        }

        return preferences
    }

    func savePreferences(_ preferences: AppPreferences) {
        if let data = try? JSONEncoder().encode(preferences.hotkeys) {
            defaults.set(data, forKey: hotkeyBindingsKey)
        }
        defaults.set(preferences.languageMode.rawValue, forKey: languageModeKey)
        defaults.set(preferences.cleanupLevel.rawValue, forKey: cleanupLevelKey)
        defaults.set(preferences.showFlowBar, forKey: showFlowBarKey)
        defaults.set(preferences.transcriptionQuality.rawValue, forKey: transcriptionQualityKey)

        if let selectedInputDeviceID = preferences.selectedInputDeviceID {
            defaults.set(selectedInputDeviceID, forKey: selectedInputDeviceIDKey)
        } else {
            defaults.removeObject(forKey: selectedInputDeviceIDKey)
        }

        if let commandHotkey = preferences.commandHotkey,
           let data = try? JSONEncoder().encode(commandHotkey) {
            defaults.set(data, forKey: commandBindingKey)
        } else {
            defaults.removeObject(forKey: commandBindingKey)
        }
    }
}
