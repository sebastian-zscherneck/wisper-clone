import Foundation

/// Decides whether a dictation result gets the signature appended, and composes the
/// combined text. Pure and free of AppKit so the app-matching rules stay unit-testable.
enum SignatureAppender {
    /// True when `settings` say the signature belongs in the app identified by `bundleID`.
    /// Matching is a case-insensitive bundle-ID prefix, so a configured "com.jetbrains."
    /// covers every JetBrains IDE. Fails closed: an unknown bundle ID never matches.
    static func shouldAppend(settings: SignatureSettings, bundleID: String?) -> Bool {
        guard settings.isAutoAppendEnabled, !settings.trimmedText.isEmpty else { return false }
        guard let bundleID else { return false }
        let lowercasedBundleID = bundleID.lowercased()
        return settings.apps.contains { lowercasedBundleID.hasPrefix($0.bundleID.lowercased()) }
    }

    /// Appends `signature` to `text`, separated by `separator`. Skips the append when the
    /// text already ends with the signature so dictating twice into the same draft — or
    /// re-pasting the last transcript — never stacks duplicates.
    static func append(_ signature: String, to text: String, separator: SignatureSeparator) -> String {
        let trimmedSignature = signature.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSignature.isEmpty else { return trimmedText }
        guard !trimmedText.isEmpty else { return trimmedSignature }
        guard !trimmedText.lowercased().hasSuffix(trimmedSignature.lowercased()) else { return trimmedText }
        return trimmedText + separator.text + trimmedSignature
    }
}
