import Foundation
import SpeakorbCore

/// DeepSeek：只有文字对话、没有音频输入（官方价目页的能力表只有 Vision）。所以它只做两段式的第二跳：
/// 本机转写出的原文交给它润色；传录音进来直接拒绝，不去发一个注定 400 的请求。
public final class DeepSeekProvider: OpenAICompatibleProvider {
    public init(
        key: String?,
        transport: HTTPTransport = URLSessionTransport(),
        model: String = ProviderDefaults.deepSeekModel,
        baseURL: URL = ProviderDefaults.deepSeekBaseURL
    ) {
        super.init(id: .deepseek, key: key, transport: transport, model: model, baseURL: baseURL, supportsAudio: false)
    }
}
