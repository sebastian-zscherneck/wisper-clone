import Foundation
import Testing
@testable import wisper_clone

@Test func preferencesStore_roundTripsCleanupLevel() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    var preferences = AppPreferences()
    preferences.cleanupLevel = .medium
    store.savePreferences(preferences)

    #expect(store.loadPreferences().cleanupLevel == .medium)
}

@Test func preferencesStore_defaultsCleanupLevelToNone() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    #expect(store.loadPreferences().cleanupLevel == .none)
}

@Test func preferencesStore_defaultsShowFlowBarToTrue() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    #expect(store.loadPreferences().showFlowBar == true)
}

@Test func preferencesStore_roundTripsShowFlowBar() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    var preferences = AppPreferences()
    preferences.showFlowBar = false
    store.savePreferences(preferences)

    #expect(store.loadPreferences().showFlowBar == false)
}

@Test func preferencesStore_roundTripsCommandHotkey() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    var preferences = AppPreferences()
    preferences.commandHotkey = .fnControl
    store.savePreferences(preferences)

    #expect(store.loadPreferences().commandHotkey == .fnControl)
}

@Test func preferencesStore_defaultsCommandHotkeyToNil() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    #expect(store.loadPreferences().commandHotkey == nil)
}

@Test func preferencesStore_defaultsTranscriptionQualityToAccurate() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    #expect(store.loadPreferences().transcriptionQuality == .accurate)
}

@Test func preferencesStore_roundTripsTranscriptionQuality() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    var preferences = AppPreferences()
    preferences.transcriptionQuality = .fast
    store.savePreferences(preferences)

    #expect(store.loadPreferences().transcriptionQuality == .fast)
}

@Test func preferencesStore_clearsCommandHotkeyBackToNil() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    var preferences = AppPreferences()
    preferences.commandHotkey = .fnControl
    store.savePreferences(preferences)

    preferences.commandHotkey = nil
    store.savePreferences(preferences)

    #expect(store.loadPreferences().commandHotkey == nil)
}

@Test func preferencesStore_defaultsSignatureToDisabledWithPresetApps() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    let signature = store.loadPreferences().signature
    #expect(signature.isAutoAppendEnabled == false)
    #expect(signature.apps == SignatureApp.defaults)
    #expect(store.loadPreferences().signatureHotkey == nil)
}

@Test func preferencesStore_roundTripsSignatureSettings() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    var preferences = AppPreferences()
    preferences.signature.isAutoAppendEnabled = true
    preferences.signature.text = "— dictated with WisprFlow"
    preferences.signature.separator = .blankLine
    preferences.signature.apps = [SignatureApp(bundleID: "notion.id", name: "Notion")]
    preferences.signatureHotkey = .shiftMouse5
    store.savePreferences(preferences)

    let loaded = store.loadPreferences()
    #expect(loaded.signature == preferences.signature)
    #expect(loaded.signatureHotkey == .shiftMouse5)
}

@Test func preferencesStore_clearsSignatureHotkeyBackToNil() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    var preferences = AppPreferences()
    preferences.signatureHotkey = .fnControl
    store.savePreferences(preferences)

    preferences.signatureHotkey = nil
    store.savePreferences(preferences)

    #expect(store.loadPreferences().signatureHotkey == nil)
}

@Test func preferencesStore_keepsSignatureDefaultsWhenStoredBlobIsPartial() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data(#"{"isAutoAppendEnabled":true}"#.utf8), forKey: "preferences.signature")
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    let signature = store.loadPreferences().signature
    #expect(signature.isAutoAppendEnabled == true)
    #expect(signature.text == "Made with WisprFlow")
    #expect(signature.separator == .newline)
    #expect(signature.apps == SignatureApp.defaults)
}

@Test func preferencesStore_migratesLegacyHotkeyStringsToBindings() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(["fn", "optionSpace"], forKey: "preferences.hotkeys")
    defaults.set("shiftMouse5", forKey: "preferences.commandHotkey")
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    let preferences = store.loadPreferences()

    #expect(Set(preferences.hotkeys) == Set([HotkeyBinding.fn, .optionSpace]))
    #expect(preferences.commandHotkey == .shiftMouse5)
}

@Test func preferencesStore_roundTripsCustomBindings() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    let custom = HotkeyBinding(trigger: .key(code: 15), modifiers: [.command, .option])
    var preferences = AppPreferences()
    preferences.hotkeys = [custom, .mouse5]
    preferences.commandHotkey = HotkeyBinding(trigger: .mouseButton(number: 3), modifiers: [.control])
    store.savePreferences(preferences)

    let loaded = store.loadPreferences()
    #expect(loaded.hotkeys == [custom, .mouse5])
    #expect(loaded.commandHotkey == HotkeyBinding(trigger: .mouseButton(number: 3), modifiers: [.control]))
}

@Test func preferencesStore_savedBindingsWinOverLegacyStrings() throws {
    let suiteName = "wisper-clone-preferences-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(["controlSpace"], forKey: "preferences.hotkeys")
    let store = UserDefaultsAppPreferencesStore(defaults: defaults)

    var preferences = AppPreferences()
    preferences.hotkeys = [.mouse5]
    store.savePreferences(preferences)

    #expect(store.loadPreferences().hotkeys == [HotkeyBinding.mouse5])
}
