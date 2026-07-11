import Foundation
import Testing
@testable import wisper_clone

@Test func personalRulesStore_defaultsToEmpty() throws {
    let suiteName = "wisper-clone-rules-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PersonalRulesStore(defaults: defaults)

    #expect(store.loadRules().isEmpty)
}

@Test func personalRulesStore_roundTripsRules() throws {
    let suiteName = "wisper-clone-rules-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PersonalRulesStore(defaults: defaults)

    store.saveRules(["never use exclamation marks", "always say hi"])

    #expect(store.loadRules() == ["never use exclamation marks", "always say hi"])
}

@Test func personalRulesStore_deduplicatesCaseInsensitively() throws {
    let suiteName = "wisper-clone-rules-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PersonalRulesStore(defaults: defaults)

    store.saveRules(["Never use exclamation marks", "never use exclamation marks"])

    #expect(store.loadRules() == ["Never use exclamation marks"])
}
