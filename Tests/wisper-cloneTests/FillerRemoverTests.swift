import Testing
@testable import wisper_clone

@Test func fillerRemover_removesHesitationSoundsAndRepairsSentenceStart() {
    #expect(FillerRemover.clean("Ähm, ich schicke dir das äh morgen.") == "Ich schicke dir das morgen.")
    #expect(FillerRemover.clean("Das passt. Hm, wir sehen uns dann.") == "Das passt. Wir sehen uns dann.")
}

@Test func fillerRemover_collapsesRepeatedWords() {
    #expect(FillerRemover.clean("Ich schick dir das das Deck gleich.") == "Ich schick dir das Deck gleich.")
    #expect(FillerRemover.clean("I I think that works") == "I think that works")
}

@Test func fillerRemover_keepsRealWordsThatLookLikeFillers() {
    let text = "Er kommt um neun, um das zu klären, und die, die fehlen, rufen an."
    #expect(FillerRemover.clean(text) == text)
    #expect(FillerRemover.clean("Der Uhrmacher hat ähnliche Uhren.") == "Der Uhrmacher hat ähnliche Uhren.")
}

@Test func fillerRemover_leavesCleanTextUntouched() {
    let text = "kurzes update: alles läuft. mehr dazu morgen."
    #expect(FillerRemover.clean(text) == text)
}
