import Foundation

protocol AppPreferencesStoring {
    func loadPreferences() -> AppPreferences
    func savePreferences(_ preferences: AppPreferences)
}

struct UserDefaultsAppPreferencesStore: AppPreferencesStoring {
    private let defaults: UserDefaults
    private let hotkeysKey = "preferences.hotkeys"
    private let languageModeKey = "preferences.languageMode"
    private let selectedInputDeviceIDKey = "preferences.selectedInputDeviceID"
    private let cleanupLevelKey = "preferences.cleanupLevel"
    private let commandHotkeyKey = "preferences.commandHotkey"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPreferences() -> AppPreferences {
        var preferences = AppPreferences()

        if let rawHotkeys = defaults.stringArray(forKey: hotkeysKey) {
            let hotkeys = Set(rawHotkeys.compactMap(Hotkey.init(rawValue:)))
            if !hotkeys.isEmpty {
                preferences.hotkeys = hotkeys
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

        if let rawCommandHotkey = defaults.string(forKey: commandHotkeyKey) {
            preferences.commandHotkey = Hotkey(rawValue: rawCommandHotkey)
        }

        return preferences
    }

    func savePreferences(_ preferences: AppPreferences) {
        defaults.set(preferences.hotkeys.map(\.rawValue).sorted(), forKey: hotkeysKey)
        defaults.set(preferences.languageMode.rawValue, forKey: languageModeKey)
        defaults.set(preferences.cleanupLevel.rawValue, forKey: cleanupLevelKey)

        if let selectedInputDeviceID = preferences.selectedInputDeviceID {
            defaults.set(selectedInputDeviceID, forKey: selectedInputDeviceIDKey)
        } else {
            defaults.removeObject(forKey: selectedInputDeviceIDKey)
        }

        if let commandHotkey = preferences.commandHotkey {
            defaults.set(commandHotkey.rawValue, forKey: commandHotkeyKey)
        } else {
            defaults.removeObject(forKey: commandHotkeyKey)
        }
    }
}
