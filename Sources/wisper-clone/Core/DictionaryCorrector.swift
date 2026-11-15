import Foundation

/// Rewrites near-misses of dictionary terms to their exact spelling, without a language
/// model. The local speech model takes no vocabulary, so names come back misheard
/// ("Flobar" for "Flow Bar"). Comparison ignores case, accents and spaces.
enum DictionaryCorrector {
    /// Shorter terms are too easy to confuse with ordinary words.
    static let minimumTermLength = 6

    static func apply(_ text: String, terms: [String]) -> String {
        let entries = terms
            .map { Entry(term: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0.key.count >= minimumTermLength }
            .sorted { $0.key.count > $1.key.count }
        guard !entries.isEmpty else { return text }
        let knownKeys = Set(entries.map(\.key))

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { correctLine(String($0), entries: entries, knownKeys: knownKeys) }
            .joined(separator: "\n")
    }

    private struct Entry {
        let term: String
        let key: [Character]
        let wordCount: Int

        init(term: String) {
            self.term = term
            key = Array(DictionaryCorrector.key(for: term))
            wordCount = max(1, term.split(whereSeparator: \.isWhitespace).count)
        }
    }

    private struct Token {
        var leading: String
        var core: String
        var trailing: String
    }

    private static func correctLine(_ line: String, entries: [Entry], knownKeys: Set<[Character]>) -> String {
        var tokens = line.split(separator: " ", omittingEmptySubsequences: false).map { token(from: String($0)) }

        for entry in entries {
            var index = 0
            while index < tokens.count {
                // Of all window widths starting here, take the closest match. A wider
                // window must not win just because it is still within tolerance, or it
                // would swallow the neighbouring word.
                var best: (width: Int, distance: Int)?
                for width in 1...min(entry.wordCount + 1, tokens.count - index) {
                    let window = tokens[index..<(index + width)]
                    // Punctuation inside the window means the words belong to different phrases.
                    let hasInnerPunctuation = window.dropLast().contains { !$0.trailing.isEmpty }
                        || window.dropFirst().contains { !$0.leading.isEmpty }
                    guard !hasInnerPunctuation else { break }

                    let candidate = Array(key(for: window.map(\.core).joined()))
                    guard let distance = nearMissDistance(candidate, of: entry.key, knownKeys: knownKeys) else { continue }
                    if best == nil || distance < best!.distance {
                        best = (width, distance)
                    }
                }

                if let best {
                    let window = tokens[index..<(index + best.width)]
                    let merged = Token(leading: window.first?.leading ?? "", core: entry.term, trailing: window.last?.trailing ?? "")
                    tokens.replaceSubrange(index..<(index + best.width), with: [merged])
                }
                index += 1
            }
        }

        return tokens.map { $0.leading + $0.core + $0.trailing }.joined(separator: " ")
    }

    /// Edit distance when `candidate` is close enough to `key` to count as a mishearing.
    private static func nearMissDistance(_ candidate: [Character], of key: [Character], knownKeys: Set<[Character]>) -> Int? {
        guard candidate.count >= minimumTermLength - 1, candidate.first == key.first else { return nil }
        if candidate == key { return 0 }
        // Another dictionary term spelled correctly is never a misspelling of this one.
        guard !knownKeys.contains(candidate) else { return nil }
        let longest = max(candidate.count, key.count)
        let allowed = longest < 8 ? 1 : longest < 12 ? 2 : longest / 3
        let distance = editDistance(candidate, key, limit: allowed)
        return distance <= allowed ? distance : nil
    }

    private static func key(for text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func token(from raw: String) -> Token {
        let characters = Array(raw)
        var start = 0
        var end = characters.count
        while start < end, !(characters[start].isLetter || characters[start].isNumber) { start += 1 }
        while end > start, !(characters[end - 1].isLetter || characters[end - 1].isNumber) { end -= 1 }
        return Token(
            leading: String(characters[..<start]),
            core: String(characters[start..<end]),
            trailing: String(characters[end...])
        )
    }

    /// Levenshtein distance; stops early once every path exceeds `limit`.
    private static func editDistance(_ lhs: [Character], _ rhs: [Character], limit: Int) -> Int {
        guard abs(lhs.count - rhs.count) <= limit else { return limit + 1 }
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1]
            current.reserveCapacity(rhs.count + 1)
            for (j, right) in rhs.enumerated() {
                current.append(min(previous[j] + (left == right ? 0 : 1), previous[j + 1] + 1, current[j] + 1))
            }
            guard (current.min() ?? 0) <= limit else { return limit + 1 }
            previous = current
        }
        return previous[rhs.count]
    }
}
