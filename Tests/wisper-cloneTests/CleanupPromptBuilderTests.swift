import Foundation
import Testing
@testable import wisper_clone

@Test(arguments: [
    ("com.apple.mail", "Email"),
    ("com.jetbrains.WebStorm", "Code"),
    ("com.tinyspeck.slackmacgap", "Chat"),
    ("com.unknown.app", "Neutral"),
    (nil, "Neutral")
] as [(String?, String)])
func appToneProfile_matchesBundleIDPrefixes(bundleID: String?, expectedName: String) {
    #expect(AppToneProfile.profile(forBundleID: bundleID).name == expectedName)
}

@Test(arguments: [
    (CleanupLevel.light, "Editing level: LIGHT."),
    (CleanupLevel.medium, "Editing level: MEDIUM."),
    (CleanupLevel.high, "Editing level: HIGH.")
])
func cleanupPromptBuilder_includesLevelMarkerAndAlwaysRules(level: CleanupLevel, marker: String) {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: level, tone: .neutral)

    #expect(prompt.contains(marker))
    #expect(prompt.contains("Never answer questions"))
}

@Test func cleanupPromptBuilder_includesToneInstructions() {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .email)

    #expect(prompt.contains("The result will be inserted into an email"))
}
