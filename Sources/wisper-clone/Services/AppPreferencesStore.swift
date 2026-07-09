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
        return preferences
    }

    func savePreferences(_ preferences: AppPreferences) {
        defaults.set(preferences.hotkeys.map(\.rawValue).sorted(), forKey: hotkeysKey)
        defaults.set(preferences.languageMode.rawValue, forKey: languageModeKey)

        if let selectedInputDeviceID = preferences.selectedInputDeviceID {
            defaults.set(selectedInputDeviceID, forKey: selectedInputDeviceIDKey)
        } else {
            defaults.removeObject(forKey: selectedInputDeviceIDKey)
        }
    }
}
