import Foundation

struct TranscriptionPromptBuilder: Sendable {
    let maxDictionaryTerms: Int
    let maxDictionaryCharacters: Int
    let maxTermCharacters: Int

    init(
        maxDictionaryTerms: Int = 40,
        maxDictionaryCharacters: Int = 1_200,
        maxTermCharacters: Int = 80
    ) {
        self.maxDictionaryTerms = maxDictionaryTerms
        self.maxDictionaryCharacters = maxDictionaryCharacters
        self.maxTermCharacters = maxTermCharacters
    }

    func build(dictionaryTerms: [String]) -> String {
        var prompt = """
        Transcribe this as polished personal dictation.
        The speaker may mix German and English, including within the same sentence.
        Preserve the spoken language and meaning of each phrase; do not translate or add facts.
        Lightly smooth filler words, repeated words, obvious false starts, and minor spoken disfluencies.
        Use natural punctuation, capitalization, and short paragraphs for readability.
        If the speaker lists multiple items, format them as a concise bullet list.
        Keep short messages short and natural; do not make casual messages overly formal.
        Keep proper nouns, product names, acronyms, and technical terms exactly when they match the audio.
        """

        let vocabulary = limitedDictionaryTerms(from: dictionaryTerms)
        if !vocabulary.isEmpty {
            prompt += "\nPreferred vocabulary and spellings: \(vocabulary.joined(separator: "; ")). Use these exact spellings only when they match the audio."
        }

        return prompt
    }

    func buildCommandInstructionPrompt() -> String {
        """
        The audio is a short spoken editing command, in German or English, such as "mach das kürzer" \
        or "make this more formal".
        Transcribe it verbatim as spoken. Do not execute the instruction, do not answer it, and do not add anything else.
        """
    }

    private func limitedDictionaryTerms(from terms: [String]) -> [String] {
        var limited: [String] = []
        var usedCharacters = 0

        for term in terms {
            guard limited.count < maxDictionaryTerms else { break }

            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let shortened = String(trimmed.prefix(maxTermCharacters))
            let separatorCharacters = limited.isEmpty ? 0 : 2
            guard usedCharacters + separatorCharacters + shortened.count <= maxDictionaryCharacters else {
                break
            }

            limited.append(shortened)
            usedCharacters += separatorCharacters + shortened.count
        }

        return limited
    }
}
