import Foundation

struct PersonalDictionaryStore {
    private let defaults: UserDefaults
    private let key = "personalDictionaryTerms"
    private let defaultTerms = [
        "n8n",
        "Claude",
        "Sebastian Zscherneck"
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadTerms() -> [String] {
        guard let saved = defaults.stringArray(forKey: key) else {
            saveTerms(defaultTerms)
            return defaultTerms
        }
        return normalize(saved)
    }

    func saveTerms(_ terms: [String]) {
        defaults.set(normalize(terms), forKey: key)
    }

    private func normalize(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let identity = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(identity) else { continue }
            seen.insert(identity)
            normalized.append(trimmed)
        }

        return normalized
    }
}
