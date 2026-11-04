import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case local
    case gemini
    case openai
    case openrouter
    case deepseek
    case bailian
    case custom
}

public enum Route: String, Codable, Sendable {
    case local
    case cloudDirect
    case cloudPolish
}

public enum AudioContainer: String, Codable, Sendable {
    case wav
    case opus
    case webm
}

public struct AudioPayload: Equatable, Sendable {
    public var data: Data
    public var sampleRate: Int
    public var channels: Int
    public var container: AudioContainer
    public var durationMs: Int

    public init(data: Data, sampleRate: Int = 16_000, channels: Int = 1, container: AudioContainer = .wav, durationMs: Int) {
        self.data = data
        self.sampleRate = sampleRate
        self.channels = channels
        self.container = container
        self.durationMs = durationMs
    }
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var id: ProviderID
    public var model: String
    public var baseURL: String?
    public var enabled: Bool

    public init(id: ProviderID, model: String, baseURL: String? = nil, enabled: Bool = true) {
        self.id = id
        self.model = model
        self.baseURL = baseURL
        self.enabled = enabled
    }
}

/// 听写语言（你说哪种话），和界面语言无关。存进 AppSettings.language 的是 rawValue。
public enum DictationLanguage: String, CaseIterable, Sendable {
    /// 普通话；夹杂的英文词也能认出。
    case chinese = "zh-CN"
    case english = "en-US"

    /// 认 "zh"、"zh-CN"、"zh_Hans"、"en"、"en-GB" 这类写法；认不出时按中文（老版本的默认）。
    public init(code: String) {
        let lower = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = lower.hasPrefix("en") ? .english : .chinese
    }
}

public struct ProviderOptions: Equatable, Sendable {
    public var language: String
    public var glossary: [DictionaryEntry]
    public var timeout: TimeInterval

    public init(language: String = "zh", glossary: [DictionaryEntry] = [], timeout: TimeInterval = 25) {
        self.language = language
        self.glossary = glossary
        self.timeout = timeout
    }
}

public struct DictionaryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var term: String
    public var note: String

    public init(id: UUID = UUID(), term: String, note: String = "") {
        self.id = id
        self.term = term
        self.note = note
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var preferredProvider: ProviderID
    public var allowCloud: Bool
    public var language: String
    public var hotkey: String
    public var launchAtLogin: Bool
    public var maxRecordingSeconds: Int
    public var dictionary: [DictionaryEntry]
    public var customBaseURL: String
    public var customModel: String

    public init(
        preferredProvider: ProviderID = .local,
        allowCloud: Bool = true,
        language: String = "zh-CN",
        hotkey: String = "rightOption",
        launchAtLogin: Bool = false,
        maxRecordingSeconds: Int = 180,
        dictionary: [DictionaryEntry] = [],
        customBaseURL: String = "",
        customModel: String = ""
    ) {
        self.preferredProvider = preferredProvider
        self.allowCloud = allowCloud
        self.language = language
        self.hotkey = hotkey
        self.launchAtLogin = launchAtLogin
        self.maxRecordingSeconds = maxRecordingSeconds
        self.dictionary = dictionary
        self.customBaseURL = customBaseURL
        self.customModel = customModel
    }

    private enum CodingKeys: String, CodingKey {
        case preferredProvider, allowCloud, language, hotkey, launchAtLogin, maxRecordingSeconds, dictionary, customBaseURL, customModel
    }

    /// 兼容旧版本设置文件（没有 dictionary 字段时回退为空数组）。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preferredProvider = try c.decodeIfPresent(ProviderID.self, forKey: .preferredProvider) ?? .local
        allowCloud = try c.decodeIfPresent(Bool.self, forKey: .allowCloud) ?? true
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "zh-CN"
        hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey) ?? "rightOption"
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        maxRecordingSeconds = try c.decodeIfPresent(Int.self, forKey: .maxRecordingSeconds) ?? 180
        dictionary = try c.decodeIfPresent([DictionaryEntry].self, forKey: .dictionary) ?? []
        customBaseURL = try c.decodeIfPresent(String.self, forKey: .customBaseURL) ?? ""
        customModel = try c.decodeIfPresent(String.self, forKey: .customModel) ?? ""
    }
}

public struct TranscriptRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var provider: ProviderID
    public var route: Route
    public var durationMs: Int
    public var latencyMs: Int

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date(), provider: ProviderID, route: Route, durationMs: Int, latencyMs: Int) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.provider = provider
        self.route = route
        self.durationMs = durationMs
        self.latencyMs = latencyMs
    }
}
