import XCTest
@testable import SpeakorbCore

final class RouterTests: XCTestCase {
    func testLocalPreferredUsesLocalWhenAvailable() {
        let decision = Router().decide(preferred: .local, allowCloud: false, hasKey: { _ in false }, localAvailable: true)
        XCTAssertEqual(decision, .local)
    }

    func testCloudPreferredFallsBackToLocal() {
        let decision = Router().decide(preferred: .gemini, allowCloud: true, hasKey: { _ in false }, localAvailable: true)
        XCTAssertEqual(decision, .local)
    }

    func testDeepSeekRequiresLocalForPolish() {
        let decision = Router().decide(preferred: .deepseek, allowCloud: true, hasKey: { _ in true }, localAvailable: true)
        XCTAssertEqual(decision, .cloud(.deepseek, mode: .polish))
    }
}

final class RefinerTests: XCTestCase {
    func testStripsTrailingPeriods() {
        XCTAssertEqual(Refiner().postProcess("今天天气不错。"), "今天天气不错")
    }

    func testNoSpeechMarkerBecomesEmpty() {
        XCTAssertEqual(Refiner().postProcess("<无人声>"), "")
    }

    func testPromptIncludesGlossary() {
        let prompt = Refiner().prompt(language: "zh", glossary: [DictionaryEntry(term: "Speakorb")])
        XCTAssertTrue(prompt.contains("Speakorb"))
    }

    func testEnglishPromptIsEnglishWithGlossary() {
        let prompt = Refiner().prompt(language: "en-US", glossary: [DictionaryEntry(term: "Speakorb"), DictionaryEntry(term: "Gemini")])
        XCTAssertTrue(prompt.hasPrefix("You are a dictation assistant."))
        XCTAssertTrue(prompt.contains("Speakorb, Gemini"))
        XCTAssertTrue(prompt.contains("<no speech>"))
        XCTAssertFalse(prompt.contains("你是语音听写助手"))
    }

    func testChinesePromptUnchangedForChineseCodes() {
        for code in ["zh", "zh-CN", "zh_Hans", ""] {
            XCTAssertTrue(Refiner().prompt(language: code, glossary: []).hasPrefix("你是语音听写助手"), code)
        }
    }

    func testEnglishKeepsFinalPeriod() {
        XCTAssertEqual(Refiner().postProcess("Call Mom at five. Then buy milk.", language: "en-US"), "Call Mom at five. Then buy milk.")
    }

    func testChineseStillDropsFinalPeriod() {
        XCTAssertEqual(Refiner().postProcess("今天天气不错。", language: "zh-CN"), "今天天气不错")
    }

    func testEnglishNoSpeechAndPrefixAreRemoved() {
        XCTAssertEqual(Refiner().postProcess("<no speech>", language: "en-US"), "")
        XCTAssertEqual(Refiner().postProcess("<NO SPEECH>", language: "en-US"), "")
        XCTAssertEqual(Refiner().postProcess("Result: See you at noon.", language: "en-US"), "See you at noon.")
    }
}

final class DictationLanguageTests: XCTestCase {
    func testParsesCommonCodes() {
        XCTAssertEqual(DictationLanguage(code: "en"), .english)
        XCTAssertEqual(DictationLanguage(code: "en-GB"), .english)
        XCTAssertEqual(DictationLanguage(code: " EN-us "), .english)
        XCTAssertEqual(DictationLanguage(code: "zh-CN"), .chinese)
        XCTAssertEqual(DictationLanguage(code: "zh"), .chinese)
    }

    func testUnknownFallsBackToChinese() {
        XCTAssertEqual(DictationLanguage(code: ""), .chinese)
        XCTAssertEqual(DictationLanguage(code: "fr"), .chinese)
    }
}

final class WAVTests: XCTestCase {
    func testHeader() {
        let data = WAVEncoder.encode(samples: [0, 1, -1])
        XCTAssertEqual(data.count, 44 + 6)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WAVE")
    }
}
