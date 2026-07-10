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
    #expect(prompt.contains("Completeness is non-negotiable"))
}

@Test func cleanupPromptBuilder_includesToneInstructions() {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .email)

    #expect(prompt.contains("The result will be inserted into an email"))
}

@Test func cleanupPromptBuilder_chatToneKeepsAllDetails() {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .chat)

    #expect(prompt.contains("does NOT mean shorter"))
}

@Test func cleanupPromptBuilder_emailToneStructuresOwnLines() {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .email)

    #expect(prompt.contains("own line"))
}

@Test func cleanupPromptBuilder_commandSystemPromptWithSelectionAppliesInstructionToSelection() {
    let prompt = CleanupPromptBuilder().buildCommandSystemPrompt(hasSelection: true)

    #expect(prompt.contains("Apply the instruction to the selected text"))
    #expect(!prompt.contains("There is no selected text"))
}

@Test func cleanupPromptBuilder_commandSystemPromptWithoutSelectionGeneratesNewText() {
    let prompt = CleanupPromptBuilder().buildCommandSystemPrompt(hasSelection: false)

    #expect(prompt.contains("There is no selected text"))
    #expect(!prompt.contains("Apply the instruction to the selected text"))
}

@Test func cleanupPromptBuilder_commandUserMessageWithSelectionIncludesBothParts() {
    let message = CleanupPromptBuilder().buildCommandUserMessage(instruction: "make it shorter", selectedText: "Hello world")

    #expect(message == "Instruction:\nmake it shorter\n\nSelected text:\nHello world")
}

@Test func cleanupPromptBuilder_commandUserMessageWithoutSelectionMarksNoSelection() {
    let message = CleanupPromptBuilder().buildCommandUserMessage(instruction: "write a greeting", selectedText: nil)

    #expect(message == "Instruction:\nwrite a greeting\n\n(No text selected.)")
}
