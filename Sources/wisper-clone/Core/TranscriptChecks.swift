import Foundation

/// Sanity checks on model output. Both exist because small on-device models fail in
/// ways that would otherwise be pasted straight into the user's text.
enum TranscriptChecks {
    /// The local speech model picks the language itself and sometimes answers short
    /// German or English clips in another script (e.g. Cyrillic). Dictation here is
    /// German and English, so text that is mostly non-Latin is a misdetection.
    static func isMostlyNonLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard !letters.isEmpty else { return false }
        let nonLatin = letters.filter { !isLatin($0) }.count
        return Double(nonLatin) / Double(letters.count) > 0.3
    }

    private static func isLatin(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x024F || (0x1E00...0x1EFF).contains(scalar.value)
    }

    /// Light and medium cleanup must keep the speaker's words. Returns false when the
    /// cleaned text introduces too many words that were never spoken or drops too much.
    static func cleanupKeptTheWords(raw: String, cleaned: String, level: CleanupLevel) -> Bool {
        guard level == .light || level == .medium else { return true }

        let rawWords = words(raw)
        let cleanedWords = words(cleaned)
        guard !cleanedWords.isEmpty else { return false }
        guard Double(cleanedWords.count) >= Double(rawWords.count) * 0.7 else { return false }

        // Light only tidies, so almost no word may be new: one per 25 words covers
        // things like "zehn" becoming "10". Medium may fix grammar, so it gets more room.
        let allowedNewWords = level == .light
            ? max(1, cleanedWords.count / 25)
            : max(2, cleanedWords.count / 6)
        let spoken = Set(rawWords)
        let invented = cleanedWords.filter { !spoken.contains($0) }.count
        return invented <= allowedNewWords
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }
}
