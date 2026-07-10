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
