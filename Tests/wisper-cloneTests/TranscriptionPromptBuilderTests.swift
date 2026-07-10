import Foundation
import Testing
@testable import wisper_clone

@Test func transcriptionPromptBuilder_describesMixedGermanEnglishDictation() {
    let prompt = TranscriptionPromptBuilder().build(dictionaryTerms: [])

    #expect(prompt.contains("The speaker frequently mixes German and English") && prompt.contains("Examples of the expected style"))
    #expect(prompt.contains("Preserve the spoken language and meaning of each phrase; do not translate or add facts."))
    #expect(prompt.contains("Lightly smooth filler words"))
    #expect(prompt.contains("format them as a concise bullet list"))
    #expect(prompt.contains("Use natural punctuation, capitalization, and short paragraphs"))
    #expect(!prompt.contains("Preferred vocabulary"))
}

@Test func transcriptionPromptBuilder_includesTrimmedDictionaryTerms() {
    let prompt = TranscriptionPromptBuilder().build(dictionaryTerms: [
        "  n8n  ",
        "",
        "Claude",
        " Sebastian Zscherneck\n"
    ])

    #expect(prompt.contains("Preferred vocabulary and spellings: n8n; Claude; Sebastian Zscherneck."))
    #expect(prompt.contains("Use these exact spellings only when they match the audio."))
}

@Test func transcriptionPromptBuilder_limitsDictionaryPromptByTermsAndCharacters() {
    let builder = TranscriptionPromptBuilder(
        maxDictionaryTerms: 3,
        maxDictionaryCharacters: 18,
        maxTermCharacters: 6
    )

    let prompt = builder.build(dictionaryTerms: [
        "AlphaLongName",
        "BetaLongName",
        "GammaLongName",
        "DeltaLongName"
    ])

    #expect(prompt.contains("Preferred vocabulary and spellings: AlphaL; BetaLo."))
    #expect(!prompt.contains("GammaL"))
    #expect(!prompt.contains("DeltaL"))
}

@Test func transcriptionPromptBuilder_commandInstructionPromptDescribesVerbatimTranscription() {
    let prompt = TranscriptionPromptBuilder().buildCommandInstructionPrompt()

    #expect(prompt.contains("short spoken editing command"))
    #expect(prompt.contains("Transcribe it verbatim as spoken"))
    #expect(prompt.contains("Do not execute the instruction"))
}
