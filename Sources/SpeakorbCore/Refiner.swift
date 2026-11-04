import Foundation

public struct Refiner: Sendable {
    public init() {}

    /// 给接入的服务的整理提示词。中文、英文各一套，规则相同。
    public func prompt(language: String, glossary: [DictionaryEntry]) -> String {
        let dictation = DictationLanguage(code: language)
        let glossaryBlock = Glossary().promptBlock(glossary, language: dictation)
        var parts: [String]
        switch dictation {
        case .chinese:
            parts = [
                "你是语音听写助手。把用户说的话整理成可以直接发送的文字。",
                "规则：",
                "1. 保留原意，不增加事实、不回答、不解释。",
                "2. 去掉口头禅、结巴、重复和无意义语气词；改口时保留最后一次说法。",
                "3. 自动加中文标点；中英混说保留英文单词；专有名词按给定术语写。",
                "4. 一句话不换行；内容明显分点时才用列表；不要用加粗、标题。",
                "5. 只输出整理后的文字，不要输出解释、引号或代码块。",
                "6. 没有听到人声时只输出标记 <无人声>。",
            ]
        case .english:
            parts = [
                "You are a dictation assistant. Turn what the user said into text they can send as is.",
                "Rules:",
                "1. Keep the meaning. Do not add facts, answer questions or explain anything.",
                "2. Remove filler words (um, uh, like, you know), stutters and repetitions; when the speaker corrects themselves, keep only the final version.",
                "3. Write in English with normal capitalization and punctuation. Spell proper nouns as given in the term list.",
                "4. Keep a single sentence on one line; use a list only when the content is clearly a list; no bold or headings.",
                "5. Output only the cleaned-up text: no explanations, quotes or code blocks.",
                "6. If there is no speech, output only the marker <no speech>.",
            ]
        }
        if !glossaryBlock.isEmpty { parts.append(glossaryBlock) }
        parts.append(dictation == .chinese ? "语言：\(language)" : "Language: \(language)")
        return parts.joined(separator: "\n")
    }

    /// 整理输出的最后一步。中文去掉句尾句号（聊天习惯）；英文保留句号，因为多句话时只去最后一个会显得不一致。
    public func postProcess(_ raw: String, language: String = DictationLanguage.chinese.rawValue) -> String {
        let dictation = DictationLanguage(code: language)
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = text.lowercased()
        if ["<无人声>", "〈无人声〉", "<no speech>", "<no_speech>", "[no speech]"].contains(lowered) { return "" }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        // 去掉包裹的引号/代码块
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
        // 去掉模型偶尔加的前缀（如 “转写：”“Result:”）
        for prefix in ["转写：", "结果：", "整理后：", "成品：", "Transcript:", "Result:", "Output:", "Cleaned text:"]
        where text.lowercased().hasPrefix(prefix.lowercased()) {
            text.removeFirst(prefix.count)
            text = text.trimmingCharacters(in: .whitespaces)
        }
        if dictation == .chinese {
            while text.hasSuffix("。") || text.hasSuffix(".") {
                text.removeLast()
            }
        }
        // 折叠多余空格
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func looksEmpty(_ text: String) -> Bool {
        postProcess(text).isEmpty
    }
}
