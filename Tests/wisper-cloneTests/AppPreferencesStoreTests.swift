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
