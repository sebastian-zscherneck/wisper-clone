import Foundation
import Testing
@testable import wisper_clone

@Test func textCleaner_keepsSingleLineCleanupCompact() {
    let cleaned = TextCleaner.clean("  hello   world ! \n")

    #expect(cleaned == "hello world!")
}

@Test func textCleaner_preservesParagraphs() {
    let cleaned = TextCleaner.clean("  Hallo   Welt . \n\n  Neuer   Absatz !  ")

    #expect(cleaned == "Hallo Welt.\n\nNeuer Absatz!")
}

@Test func textCleaner_preservesBulletLists() {
    let cleaned = TextCleaner.clean(" Dinge : \n -   Alpha \n - Beta  ")

    #expect(cleaned == "Dinge:\n- Alpha\n- Beta")
}

@Test func textCleaner_limitsExcessBlankLines() {
    let cleaned = TextCleaner.clean("Eins\n\n\n\nZwei")

    #expect(cleaned == "Eins\n\nZwei")
}
