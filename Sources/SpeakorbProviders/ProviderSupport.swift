import Foundation
import SpeakorbCore

/// 六家共用的请求拼装与错误映射：状态码、JSON、超时、key 检查只写一遍。
enum ProviderSupport {
    /// 一次请求的默认预算：任务定的 25 秒。
    static let defaultTimeout: TimeInterval = 25

    /// 一次请求能用多久：没给（<= 0）按 25 秒。
    static func timeout(_ options: ProviderOptions) -> TimeInterval {
        options.timeout > 0 ? options.timeout : defaultTimeout
    }

    /// key 去空白；没有就在发请求之前抛 missingAPIKey。
    static func apiKey(_ key: String?, provider: ProviderID) throws -> String {
        guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeakorbError.missingAPIKey(provider)
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 拼地址时不让 base 末尾的斜杠和 path 前的斜杠叠成两个。
    static func endpoint(base: URL, path: String) -> String {
        let text = base.absoluteString
        let trimmed = text.hasSuffix("/") ? String(text.dropLast()) : text
        return "\(trimmed)/\(path)"
    }

    static func url(_ string: String, provider: ProviderID) throws -> URL {
        guard let url = URL(string: string) else {
            throw SpeakorbError.providerRejected(provider, "服务地址不对：\(string)")
        }
        return url
    }

    static func jsonRequest(url: URL, headers: [String: String], body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// 发出去、收回来，把传输层和 HTTP 状态码的错都翻成 SpeakorbError。
    static func send(
        _ transport: HTTPTransport,
        request: URLRequest,
        timeout: TimeInterval,
        provider: ProviderID
    ) async throws -> [String: Any] {
        let response: HTTPResponse
        do {
            response = try await transport.send(request, timeout: timeout)
        } catch let error as SpeakorbError {
            throw error
        } catch let error as URLError {
            // 传输层没自己翻的 URLError 在这里兜底，保证调用方看到的一定是 SpeakorbError。
            if error.code == .timedOut { throw SpeakorbError.timedOut }
            throw SpeakorbError.networkUnavailable
        } catch {
            throw SpeakorbError.networkUnavailable
        }

        let json = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any]
        guard (200...299).contains(response.statusCode) else {
            throw statusError(response.statusCode, provider: provider, json: json, data: response.data)
        }
        guard let json else {
            throw SpeakorbError.providerRejected(provider, "响应不是 JSON")
        }
        return json
    }

    /// 映射规矩（任务定的）：401/403 是钥匙不对；429 和 5xx 是服务暂时用不了；
    /// 其余 4xx（模型名写错、参数不对）也算拒绝，只是原因不一样。
    static func statusError(_ status: Int, provider: ProviderID, json: [String: Any]?, data: Data) -> SpeakorbError {
        switch status {
        case 401, 403:
            return .invalidAPIKey(provider)
        case 429, 500...599:
            return .providerRejected(provider, message(json: json, data: data))
        default:
            return .providerRejected(provider, message(json: json, data: data))
        }
    }

    /// 各家报错都是 {"error":{"message":"…"}}；不是 JSON 时退回正文前 200 字。
    static func message(json: [String: Any]?, data: Data) -> String {
        if let error = json?["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty
        {
            return message
        }
        if let message = json?["message"] as? String, !message.isEmpty {
            return message
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "服务拒绝了请求" : String(raw.prefix(200))
    }

    /// OpenAI 兼容那几家：choices[0].message.content 可能是字符串，也可能是分片数组。
    static func choicesText(_ json: [String: Any], provider: ProviderID) throws -> String {
        guard let choices = json["choices"] as? [[String: Any]], let choice = choices.first else {
            throw SpeakorbError.providerRejected(provider, "响应里没有 choices")
        }
        if let finish = choice["finish_reason"] as? String, finish == "content_filter" {
            throw SpeakorbError.providerRejected(provider, "内容被拦下（content_filter）")
        }
        guard let message = choice["message"] as? [String: Any] else {
            throw SpeakorbError.providerRejected(provider, "响应里没有 message")
        }
        var text = ""
        if let content = message["content"] as? String {
            text = content
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeakorbError.providerRejected(provider, "模型没有返回文字")
        }
        return text
    }
}

/// 录音在请求体里的写法：OpenAI 是 base64 + format，百炼要 data URI（实测见实现笔记）。
public enum AudioPayloadEncoding: Sendable {
    case base64WithFormat
    case dataURI
}
