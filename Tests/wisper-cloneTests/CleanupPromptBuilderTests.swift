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
    ("com.google.chrome", "Posteingang – Gmail", "Email"),
    ("com.google.chrome", "YouTube", "Neutral"),
    ("com.apple.safari", "Compose Mail", "Email"),
    ("com.apple.mail", nil, "Email"),
    ("com.google.chrome", "Mailchimp Campaign Builder", "Neutral"),
    ("com.apple.safari", "Neue Mailingliste erstellen", "Neutral")
] as [(String, String?, String)])
func appToneProfile_detectsBrowserEmailViaWindowTitle(bundleID: String, windowTitle: String?, expectedName: String) {
    #expect(AppToneProfile.profile(forBundleID: bundleID, windowTitle: windowTitle).name == expectedName)
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

@Test func cleanupPromptBuilder_includesVocabularyWhenProvided() {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .neutral, vocabulary: ["n8n", "sellerboard"])

    #expect(prompt.contains("Known terms the speaker uses"))
    #expect(prompt.contains("n8n"))
    #expect(prompt.contains("sellerboard"))
}

@Test func cleanupPromptBuilder_omitsVocabularyBlockWhenEmpty() {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .neutral, vocabulary: [])

    #expect(!prompt.contains("Known terms the speaker uses"))
}

@Test func cleanupPromptBuilder_capsVocabularyAtMaxTerms() {
    let terms = (0..<50).map { "term\($0)" }
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .neutral, vocabulary: terms)

    #expect(prompt.contains("term0"))
    #expect(prompt.contains("term39"))
    #expect(!prompt.contains("term40"))
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

@Test func cleanupPromptBuilder_includesRulesWhenProvided() {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .neutral, rules: ["never use exclamation marks", "always say hi"])

    #expect(prompt.contains("User-defined rules that always apply"))
    #expect(prompt.contains("- never use exclamation marks"))
    #expect(prompt.contains("- always say hi"))
}

@Test func cleanupPromptBuilder_omitsRulesBlockWhenEmpty() {
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .neutral, rules: [])

    #expect(!prompt.contains("User-defined rules"))
}

@Test func cleanupPromptBuilder_capsRulesAtMaxCount() {
    let rules = (0..<30).map { "rule\($0)" }
    let prompt = CleanupPromptBuilder().buildSystemPrompt(level: .medium, tone: .neutral, rules: rules)

    #expect(prompt.contains("rule0"))
    #expect(prompt.contains("rule19"))
    #expect(!prompt.contains("rule20"))
}

@Test func cleanupPromptBuilder_commandSystemPromptIncludesRulesAndAppContext() {
    let prompt = CleanupPromptBuilder().buildCommandSystemPrompt(
        hasSelection: true,
        appContext: "Context: the result will be inserted into Mail (window: \"Compose\"). Match the conventions of that context.",
        rules: ["never use exclamation marks"]
    )

    #expect(prompt.contains("Context: the result will be inserted into Mail"))
    #expect(prompt.contains("User-defined rules that always apply"))
    #expect(prompt.contains("- never use exclamation marks"))
}

@Test func cleanupPromptBuilder_commandSystemPromptOmitsAppContextAndRulesWhenAbsent() {
    let prompt = CleanupPromptBuilder().buildCommandSystemPrompt(hasSelection: true)

    #expect(!prompt.contains("Context: the result will be inserted into"))
    #expect(!prompt.contains("User-defined rules"))
}

@Test func cleanupPromptBuilder_commandUserMessageWithoutSelectionIncludesLastTranscript() {
    let message = CleanupPromptBuilder().buildCommandUserMessage(
        instruction: "make it more formal",
        selectedText: nil,
        lastTranscript: "the meeting is at 3pm"
    )

    #expect(message.contains("For reference, the user's most recent dictation"))
    #expect(message.contains("the meeting is at 3pm"))
}

@Test func cleanupPromptBuilder_commandUserMessageWithSelectionOmitsLastTranscript() {
    let message = CleanupPromptBuilder().buildCommandUserMessage(
        instruction: "make it shorter",
        selectedText: "Hello world",
        lastTranscript: "the meeting is at 3pm"
    )

    #expect(!message.contains("For reference"))
    #expect(!message.contains("the meeting is at 3pm"))
}

@Test func localSystemPrompt_staysCompactAndCarriesVocabularyAndRules() {
    let prompt = CleanupPromptBuilder().buildLocalSystemPrompt(
        level: .medium,
        vocabulary: ["Störtebekker"],
        rules: ["Never use exclamation marks"]
    )

    #expect(prompt.contains("Never translate"))
    #expect(prompt.contains(CleanupPromptBuilder.localMediumInstructions))
    #expect(prompt.contains("Störtebekker"))
    #expect(prompt.contains("Never use exclamation marks"))
    #expect(prompt.count < CleanupPromptBuilder().buildSystemPrompt(
        level: .medium,
        tone: AppToneProfile.profile(forBundleID: nil, windowTitle: nil),
        vocabulary: ["Störtebekker"],
        rules: ["Never use exclamation marks"]
    ).count)
}

@Test func localSystemPrompt_lightLevelAddsNoExtraInstructions() {
    let prompt = CleanupPromptBuilder().buildLocalSystemPrompt(level: .light)

    #expect(prompt == CleanupPromptBuilder.localBasePrompt)
}
