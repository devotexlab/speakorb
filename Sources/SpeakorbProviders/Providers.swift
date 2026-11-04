import Foundation
import SpeakorbCore

/// 六家云提供方在这里登记：只按 id 找，构造时不联网、不读钥匙串。
public final class ProviderRegistry: ProviderResolving {
    private let providers: [CloudCompleting]

    public init(_ providers: [CloudCompleting]) {
        self.providers = providers
    }

    public func provider(for id: ProviderID) -> CloudCompleting? {
        providers.first { $0.id == id }
    }

    /// 已经登记的入口（设置页和测试用）；.local 不在这里，它走 LocalTranscribing。
    public var registeredIDs: [ProviderID] {
        ProviderID.allCases.filter { provider(for: $0) != nil }
    }
}

/// 自定义服务：地址和模型名由用户在设置里填，协议按 OpenAI 兼容处理。
public struct CustomProviderSettings: Equatable, Sendable {
    public var baseURL: URL
    public var model: String

    public init(baseURL: URL, model: String) {
        self.baseURL = baseURL
        self.model = model
    }
}

/// 出厂默认值：模型名沿用 model-options 的结论，用户可以在设置里换。
public enum ProviderDefaults {
    public static let geminiModel = "gemini-3.6-flash"
    public static let openAIModel = "gpt-audio-mini"
    public static let openRouterModel = "openai/gpt-audio-mini"
    public static let deepSeekModel = "deepseek-flash"
    public static let bailianModel = "qwen3.8-omni-flash"

    public static let geminiBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    public static let openAIBaseURL = URL(string: "https://api.openai.com/v1")!
    public static let openRouterBaseURL = URL(string: "https://openrouter.ai/api/v1")!
    public static let deepSeekBaseURL = URL(string: "https://api.deepseek.com/v1")!
    public static let bailianBaseURL = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!

    /// 自定义服务没配时用的占位地址：不会真发出去，调用前会被 CustomProvider 拦下。
    static let placeholderBaseURL = URL(string: "https://example.invalid/v1")!
    static let openRouterReferer = "https://github.com/devotexlab/speakorb"
}

/// BYOK 六入口：给一组 key 就得到能用的注册表。
/// 没有 key 的入口也照常登记：构造不抛错，等用户真用这一家时再抛 missingAPIKey，
/// 这样设置页能一次列出六家、各自显示"未配置"。
public enum ProviderFactory {
    /// 六家全登记；自定义服务没有地址，用的时候会提示去设置里填。
    public static func standard(keys: [ProviderID: String]) -> ProviderRegistry {
        standard(keys: keys, custom: nil, transport: URLSessionTransport())
    }

    /// 同上，顺便把自定义服务的地址和模型名带上。
    public static func standard(keys: [ProviderID: String], custom: CustomProviderSettings?) -> ProviderRegistry {
        standard(keys: keys, custom: custom, transport: URLSessionTransport())
    }

    /// 测试注入假 transport 用；生产走上面两个。
    public static func standard(
        keys: [ProviderID: String],
        custom: CustomProviderSettings?,
        transport: HTTPTransport
    ) -> ProviderRegistry {
        ProviderRegistry([
            GeminiProvider(key: keys[.gemini], transport: transport),
            OpenAIProvider(key: keys[.openai], transport: transport),
            OpenRouterProvider(key: keys[.openrouter], transport: transport),
            DeepSeekProvider(key: keys[.deepseek], transport: transport),
            BailianProvider(key: keys[.bailian], transport: transport),
            CustomProvider(key: keys[.custom], settings: custom, transport: transport),
        ])
    }
}
