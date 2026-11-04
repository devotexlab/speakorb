import Foundation
import SpeakorbCore

/// OpenAI 兼容的一类（OpenAI、OpenRouter、百炼、DeepSeek、自定义）：chat/completions，录音走 input_audio。
/// 四家的差别收在配置里：地址、模型、收不收录音、音频写 data URI 还是纯 base64、额外的请求字段。
public class OpenAICompatibleProvider: CloudCompleting {
    public let id: ProviderID

    let baseURL: URL
    let model: String
    let key: String?
    let transport: HTTPTransport
    /// 这家收不收录音（DeepSeek 只收文字，录音要先在本机转写）。
    let supportsAudio: Bool
    let audioEncoding: AudioPayloadEncoding
    let extraBody: [String: Any]
    let extraHeaders: [String: String]

    static let audioInstruction = "把这段录音整理成可以直接发送的文字。"

    public init(
        id: ProviderID,
        key: String?,
        transport: HTTPTransport = URLSessionTransport(),
        model: String,
        baseURL: URL,
        supportsAudio: Bool = true,
        audioEncoding: AudioPayloadEncoding = .base64WithFormat,
        extraBody: [String: Any] = [:],
        extraHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.key = key
        self.transport = transport
        self.model = model
        self.baseURL = baseURL
        self.supportsAudio = supportsAudio
        self.audioEncoding = audioEncoding
        self.extraBody = extraBody
        self.extraHeaders = extraHeaders
    }

    public func complete(
        audio: AudioPayload?,
        text: String?,
        prompt: String,
        options: ProviderOptions
    ) async throws -> String {
        let apiKey = try ProviderSupport.apiKey(key, provider: id)

        var messages: [[String: Any]] = []
        if !prompt.isEmpty {
            // 统一的 system prompt 由调用方传入（Refiner.prompt），这里不改写、不追加。
            messages.append(["role": "system", "content": prompt])
        }
        if let audio {
            guard supportsAudio else {
                throw SpeakorbError.providerRejected(id, "这家只做文字整理，要先把录音在本机转成文字")
            }
            messages.append([
                "role": "user",
                "content": [
                    ["type": "input_audio", "input_audio": audioPayload(audio)],
                    ["type": "text", "text": OpenAICompatibleProvider.audioInstruction],
                ],
            ])
        } else if let text, !text.isEmpty {
            messages.append(["role": "user", "content": text])
        } else {
            throw SpeakorbError.providerRejected(id, "没有可发送的内容")
        }

        var body: [String: Any] = ["model": model, "messages": messages, "temperature": 0]
        for (name, value) in extraBody {
            body[name] = value
        }

        let url = try ProviderSupport.url(
            ProviderSupport.endpoint(base: baseURL, path: "chat/completions"),
            provider: id
        )
        var headers = ["Authorization": "Bearer \(apiKey)"]
        for (name, value) in extraHeaders {
            headers[name] = value
        }
        let request = try ProviderSupport.jsonRequest(url: url, headers: headers, body: body)
        let json = try await ProviderSupport.send(
            transport,
            request: request,
            timeout: ProviderSupport.timeout(options),
            provider: id
        )
        return try ProviderSupport.choicesText(json, provider: id)
    }

    /// OpenAI 只收 wav 和 mp3；任务只要求 wav，别的格式照容器名写，交给厂商自己拒。
    func audioPayload(_ audio: AudioPayload) -> [String: Any] {
        let base64 = audio.data.base64EncodedString()
        let mimeType = GeminiProvider.mimeType(of: audio)
        let format: String
        switch audio.container {
        case .wav: format = "wav"
        case .opus: format = "opus"
        case .webm: format = "webm"
        }
        switch audioEncoding {
        case .base64WithFormat:
            return ["data": base64, "format": format]
        case .dataURI:
            return ["data": "data:\(mimeType);base64,\(base64)", "format": format]
        }
    }
}

/// OpenAI：gpt-audio 系列在 Chat Completions 里收音频，一次请求完成识别和整理。
public final class OpenAIProvider: OpenAICompatibleProvider {
    public init(
        key: String?,
        transport: HTTPTransport = URLSessionTransport(),
        model: String = ProviderDefaults.openAIModel,
        baseURL: URL = ProviderDefaults.openAIBaseURL
    ) {
        super.init(id: .openai, key: key, transport: transport, model: model, baseURL: baseURL)
    }
}

/// OpenRouter：聚合网关，模型名带厂商前缀；收音频的模型走 input_audio，纯文字模型走文字。
public final class OpenRouterProvider: OpenAICompatibleProvider {
    public init(
        key: String?,
        transport: HTTPTransport = URLSessionTransport(),
        model: String = ProviderDefaults.openRouterModel,
        baseURL: URL = ProviderDefaults.openRouterBaseURL
    ) {
        super.init(
            id: .openrouter,
            key: key,
            transport: transport,
            model: model,
            baseURL: baseURL,
            extraHeaders: [
                "HTTP-Referer": ProviderDefaults.openRouterReferer,
                "X-Title": "Speakorb",
            ]
        )
    }
}

/// 百炼（DashScope 的 OpenAI 兼容模式）：Qwen-Omni 在 chat/completions 里收音频。
/// 两处和 OpenAI 不同：音频写成 data URI；要 modalities: ["text"] 并关掉思考。
public final class BailianProvider: OpenAICompatibleProvider {
    public init(
        key: String?,
        transport: HTTPTransport = URLSessionTransport(),
        model: String = ProviderDefaults.bailianModel,
        baseURL: URL = ProviderDefaults.bailianBaseURL
    ) {
        super.init(
            id: .bailian,
            key: key,
            transport: transport,
            model: model,
            baseURL: baseURL,
            audioEncoding: .dataURI,
            extraBody: ["modalities": ["text"], "enable_thinking": false]
        )
    }
}

/// 自定义：地址和模型名由用户在设置里填，协议按 OpenAI 兼容处理；没配就在调用时拒绝。
public final class CustomProvider: OpenAICompatibleProvider {
    private let settings: CustomProviderSettings?

    public init(
        key: String?,
        settings: CustomProviderSettings?,
        transport: HTTPTransport = URLSessionTransport()
    ) {
        self.settings = settings
        super.init(
            id: .custom,
            key: key,
            transport: transport,
            model: settings?.model ?? "",
            baseURL: settings?.baseURL ?? ProviderDefaults.placeholderBaseURL
        )
    }

    public override func complete(
        audio: AudioPayload?,
        text: String?,
        prompt: String,
        options: ProviderOptions
    ) async throws -> String {
        guard let settings, !settings.model.isEmpty else {
            throw SpeakorbError.providerRejected(.custom, "还没配置自定义服务的地址和模型名")
        }
        return try await super.complete(audio: audio, text: text, prompt: prompt, options: options)
    }
}
