import Foundation

/// Rule-based tidying for the "Fast" local cleanup: removes hesitation sounds and words
/// that were said twice in a row. Needs no language model, so it costs no time. The speech
/// model already sets punctuation and capitalization.
enum FillerRemover {
    // Only sounds that are never a real word. "um" and "er" are German words and stay.
    private static let fillers = ["ähm", "ähh", "äh", "öhm", "öh", "ehm", "hmm", "hm", "uhm", "uhh", "uh", "erm"]

    private static let fillerPattern: NSRegularExpression = {
        let alternatives = fillers.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        // The filler with a comma or ellipsis that belongs to it, and the space after it.
        return try! NSRegularExpression(
            pattern: #"(?<![\p{L}\p{N}])(?:"# + alternatives + #")(?![\p{L}\p{N}])(?:\s*(?:,|\.\.\.|…))?\s*"#,
            options: [.caseInsensitive]
        )
    }()

    private static let repeatedWordPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])([\p{L}\p{N}]+)(?:\s+\1)+(?![\p{L}\p{N}])"#,
        options: [.caseInsensitive]
    )

    private static let sentenceStartPattern = try! NSRegularExpression(
        pattern: #"(?:^|[.!?]\s+)(\p{Ll})"#
    )

    static func clean(_ text: String) -> String {
        var cleaned = replace(fillerPattern, in: text, with: "")
        cleaned = replace(repeatedWordPattern, in: cleaned, with: "$1")
        cleaned = TextCleaner.clean(cleaned)
        // A removed filler can leave a sentence starting in lower case.
        return capitalizeSentenceStarts(in: cleaned, comparedTo: text)
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        pattern.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }

    /// Only repairs what the removal broke: text that came in lower case stays as it is.
    private static func capitalizeSentenceStarts(in text: String, comparedTo original: String) -> String {
        guard text != TextCleaner.clean(original) else { return text }
        var result = text
        let matches = sentenceStartPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(range, with: result[range].uppercased())
        }
        return result
    }
}
