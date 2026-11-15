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
    private let signatureKey = "preferences.signature"
    private let signatureBindingKey = "preferences.signatureBinding"
    private let engineKey = "preferences.engine"
    private let showInDockKey = "preferences.showInDock"
    private let showMenuBarIconKey = "preferences.showMenuBarIcon"
    private let enableSoundsKey = "preferences.enableSounds"
    private let enableHapticsKey = "preferences.enableHaptics"

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

        if let data = defaults.data(forKey: signatureKey),
           let signature = try? JSONDecoder().decode(SignatureSettings.self, from: data) {
            preferences.signature = signature
        }

        if let data = defaults.data(forKey: signatureBindingKey) {
            preferences.signatureHotkey = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
        }

        if let rawEngine = defaults.string(forKey: engineKey),
           let engine = ProcessingEngine(rawValue: rawEngine) {
            preferences.engine = engine
        }

        if defaults.object(forKey: showInDockKey) != nil {
            preferences.showInDock = defaults.bool(forKey: showInDockKey)
        }

        if defaults.object(forKey: showMenuBarIconKey) != nil {
            preferences.showMenuBarIcon = defaults.bool(forKey: showMenuBarIconKey)
        }

        if defaults.object(forKey: enableSoundsKey) != nil {
            preferences.enableSounds = defaults.bool(forKey: enableSoundsKey)
        }

        if defaults.object(forKey: enableHapticsKey) != nil {
            preferences.enableHaptics = defaults.bool(forKey: enableHapticsKey)
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
        defaults.set(preferences.engine.rawValue, forKey: engineKey)
        defaults.set(preferences.showInDock, forKey: showInDockKey)
        defaults.set(preferences.showMenuBarIcon, forKey: showMenuBarIconKey)
        defaults.set(preferences.enableSounds, forKey: enableSoundsKey)
        defaults.set(preferences.enableHaptics, forKey: enableHapticsKey)

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

        if let data = try? JSONEncoder().encode(preferences.signature) {
            defaults.set(data, forKey: signatureKey)
        }

        if let signatureHotkey = preferences.signatureHotkey,
           let data = try? JSONEncoder().encode(signatureHotkey) {
            defaults.set(data, forKey: signatureBindingKey)
        } else {
            defaults.removeObject(forKey: signatureBindingKey)
        }
    }
}
