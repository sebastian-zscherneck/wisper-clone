import Testing
@testable import wisper_clone

private let terms = ["Flow Bar", "Wispr Flow", "Claude in Chrome", "Claude", "Störtebekker", "n8n"]

@Test func dictionaryCorrector_fixesMisheardNames() {
    let text = "Die Flobar ist nicht so smooth wie die Whisper Floor. Schau es dir mit Claude and Chrome an."

    #expect(DictionaryCorrector.apply(text, terms: terms)
        == "Die Flow Bar ist nicht so smooth wie die Wispr Flow. Schau es dir mit Claude in Chrome an.")
}

@Test func dictionaryCorrector_fixesCaseAndSpacingOfExactMatches() {
    #expect(DictionaryCorrector.apply("der stoertebekker report und die flowbar", terms: terms + ["Stoertebekker"])
        .contains("Flow Bar"))
    #expect(DictionaryCorrector.apply("Bei störtebekker läuft es.", terms: terms) == "Bei Störtebekker läuft es.")
}

@Test func dictionaryCorrector_leavesOrdinaryWordsAlone() {
    let text = "Die Cloud ist teuer, Claudia weiß das. Flowers for the bar, bitte."

    #expect(DictionaryCorrector.apply(text, terms: terms) == text)
}

@Test func dictionaryCorrector_keepsPunctuationAndLineBreaks() {
    #expect(DictionaryCorrector.apply("Meinst du (Flobar)?\nJa, Flobar.", terms: terms) == "Meinst du (Flow Bar)?\nJa, Flow Bar.")
}

@Test func dictionaryCorrector_doesNotJoinWordsAcrossPunctuation() {
    let text = "Das ist Flow. Bar ist geschlossen."

    #expect(DictionaryCorrector.apply(text, terms: terms) == text)
}

@Test func dictionaryCorrector_ignoresShortTermsAndEmptyDictionary() {
    #expect(DictionaryCorrector.apply("n8m und n9n", terms: terms) == "n8m und n9n")
    #expect(DictionaryCorrector.apply("Flobar", terms: []) == "Flobar")
}

@Test func transcriptChecks_flagsWrongScriptOnly() {
    #expect(TranscriptChecks.isMostlyNonLatin("Тест, тест, тест."))
    #expect(!TranscriptChecks.isMostlyNonLatin("Test, test, über Größe und façade."))
    #expect(!TranscriptChecks.isMostlyNonLatin("123 !?"))
}

@Test func transcriptChecks_rejectsRewordedLightCleanup() {
    let raw = "Zudem sind einige Wörter falsch, überleg mal woran das liegen könnte."

    #expect(TranscriptChecks.cleanupKeptTheWords(
        raw: raw, cleaned: "Zudem sind einige Wörter falsch. Überleg mal, woran das liegen könnte.", level: .light))
    #expect(!TranscriptChecks.cleanupKeptTheWords(
        raw: raw, cleaned: "Darüber hinaus sind einige Wörter falsch, überleg mal woran das liegen könnte.", level: .light))
    #expect(!TranscriptChecks.cleanupKeptTheWords(raw: raw, cleaned: "Einige Wörter sind falsch.", level: .light))
    #expect(TranscriptChecks.cleanupKeptTheWords(raw: raw, cleaned: "Etwas völlig anderes.", level: .high))
}

@Test func transcriptChecks_rejectsSynonymSwapInLongLightCleanup() {
    let raw = "Zudem sind einige Wörter, gerade wie du diktiert, also ich habe jetzt gerade hiermit diktiert mit unserem Produkt, überleg mal, woran das liegen könnte und wie wir das verbessern könnten."
    let reworded = raw.replacingOccurrences(of: "Zudem", with: "Darüber hinaus")

    #expect(!TranscriptChecks.cleanupKeptTheWords(raw: raw, cleaned: reworded, level: .light))
    #expect(TranscriptChecks.cleanupKeptTheWords(raw: raw, cleaned: reworded, level: .medium))
    #expect(TranscriptChecks.cleanupKeptTheWords(raw: "Das Meeting ist um zehn Uhr", cleaned: "Das Meeting ist um 10 Uhr.", level: .light))
}
