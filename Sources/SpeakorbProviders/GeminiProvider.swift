import Foundation
import SpeakorbCore

/// Gemini 直出：generateContent 一次请求，录音以 inlineData（base64）交过去，系统提示词放 systemInstruction。
/// 和 OpenAI 那几家不同，Gemini 的音频与文字都在 parts 里，所以单独一个适配器。
public final class GeminiProvider: CloudCompleting {
    public let id: ProviderID = .gemini

    private let key: String?
    private let model: String
    private let baseURL: URL
    private let transport: HTTPTransport

    /// 录音后面跟的一句话：只给录音时，模型偶尔会在开头多出一个不相干的外文词（同源实现的实测结论）。
    static let audioInstruction = "把这段录音整理成可以直接发送的文字。"

    public init(
        key: String?,
        transport: HTTPTransport = URLSessionTransport(),
        model: String = ProviderDefaults.geminiModel,
        baseURL: URL = ProviderDefaults.geminiBaseURL
    ) {
        self.key = key
        self.transport = transport
        self.model = model
        self.baseURL = baseURL
    }

    public func complete(
        audio: AudioPayload?,
        text: String?,
        prompt: String,
        options: ProviderOptions
    ) async throws -> String {
        let apiKey = try ProviderSupport.apiKey(key, provider: id)

        var parts: [[String: Any]] = []
        if let audio {
            parts.append([
                "inlineData": [
                    "mimeType": GeminiProvider.mimeType(of: audio),
                    "data": audio.data.base64EncodedString(),
                ],
            ])
            parts.append(["text": GeminiProvider.audioInstruction])
        }
        if let text, !text.isEmpty {
            parts.append(["text": text])
        }
        guard !parts.isEmpty else {
            throw SpeakorbError.providerRejected(id, "没有可发送的内容")
        }

        var body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": ["temperature": 0],
        ]
        if !prompt.isEmpty {
            body["systemInstruction"] = ["parts": [["text": prompt]]]
        }

        let url = try ProviderSupport.url(
            ProviderSupport.endpoint(base: baseURL, path: "models/\(model):generateContent"),
            provider: id
        )
        // key 走请求头而不是 URL：地址会进日志和报错，放 URL 里会跟着漏出去。
        let request = try ProviderSupport.jsonRequest(url: url, headers: ["x-goog-api-key": apiKey], body: body)
        let json = try await ProviderSupport.send(
            transport,
            request: request,
            timeout: ProviderSupport.timeout(options),
            provider: id
        )

        if let feedback = json["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
            throw SpeakorbError.providerRejected(id, "内容被拦下：\(reason)")
        }
        guard let candidates = json["candidates"] as? [[String: Any]], let first = candidates.first else {
            throw SpeakorbError.providerRejected(id, "响应里没有 candidates")
        }
        if let finish = first["finishReason"] as? String, finish != "STOP" {
            // 被截断或被拦下的半截文字不能当成品贴出去。
            throw SpeakorbError.providerRejected(id, "没有正常结束：\(finish)")
        }
        guard let content = first["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]]
        else {
            throw SpeakorbError.providerRejected(id, "响应里没有 content")
        }
        let textOut = responseParts.compactMap { $0["text"] as? String }.joined()
        guard !textOut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeakorbError.providerRejected(id, "模型没有返回文字")
        }
        return textOut
    }

    /// 只收 wav（任务只要求 wav）；别的格式照容器名写 MIME，交给厂商自己拒。
    static func mimeType(of audio: AudioPayload) -> String {
        switch audio.container {
        case .wav: return "audio/wav"
        case .opus: return "audio/opus"
        case .webm: return "audio/webm"
        }
    }
}
