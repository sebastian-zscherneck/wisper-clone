import Foundation

/// Persists user-defined AI rules that always apply to cleanup and command
/// prompts (e.g. "never use exclamation marks"). Unlike PersonalDictionaryStore
/// this ships with no default rules.
struct PersonalRulesStore {
    private let defaults: UserDefaults
    private let key = "personalAIRules"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRules() -> [String] {
        guard let saved = defaults.stringArray(forKey: key) else {
            return []
        }
        return normalize(saved)
    }

    func saveRules(_ rules: [String]) {
        defaults.set(normalize(rules), forKey: key)
    }

    private func normalize(_ rules: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for rule in rules {
            let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let identity = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(identity) else { continue }
            seen.insert(identity)
            normalized.append(trimmed)
        }

        return normalized
    }
}
