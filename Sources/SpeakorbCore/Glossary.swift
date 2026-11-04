import Foundation

public struct Glossary: Sendable {
    public static let maxTerms = 200

    public init() {}

    public func normalizedTerms(_ entries: [DictionaryEntry]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !seen.contains(term) else { continue }
            seen.insert(term)
            result.append(term)
            if result.count >= Self.maxTerms { break }
        }
        return result
    }

    public func promptBlock(_ entries: [DictionaryEntry], language: DictationLanguage = .chinese) -> String {
        let terms = normalizedTerms(entries)
        guard !terms.isEmpty else { return "" }
        switch language {
        case .chinese:
            return "术语与专有名词（听到时优先按这些写法）：" + terms.joined(separator: "、")
        case .english:
            return "Terms and proper nouns (use these spellings when you hear them): " + terms.joined(separator: ", ")
        }
    }

    public func contains(term: String, in text: String) -> Bool {
        text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
