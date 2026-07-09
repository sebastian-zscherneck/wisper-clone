import Foundation

enum TextCleaner {
    static func clean(_ text: String) -> String {
        let normalizedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var cleaned = normalizedNewlines
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { cleanLine(String($0)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        return cleaned
    }

    private static func cleanLine(_ line: String) -> String {
        var cleaned = line.trimmingCharacters(in: .whitespaces)
        cleaned = cleaned.replacingOccurrences(
            of: #"[ \t]+"#,
            with: " ",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+([,.;:!?])"#,
            with: "$1",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"([({\[])\s+"#,
            with: "$1",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+([)}\]])"#,
            with: "$1",
            options: .regularExpression
        )
        return cleaned
    }
}
