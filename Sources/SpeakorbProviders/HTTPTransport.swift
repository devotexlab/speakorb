import Foundation
import SpeakorbCore

/// 一次 HTTP 回话：只留适配器用得上的两样，测试里不必造 HTTPURLResponse。
public struct HTTPResponse: Equatable, Sendable {
    public var data: Data
    public var statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

/// 网络这一层的注入点：单测换成假的，不碰真网络。
public protocol HTTPTransport: Sendable {
    /// timeout 是整次请求的预算（秒），由调用方按 ProviderOptions.timeout 传进来。
    func send(_ request: URLRequest, timeout: TimeInterval) async throws -> HTTPResponse
}

/// 真实现：URLSession。用 ephemeral 配置，不落 cookie 和缓存，key 不会随缓存进磁盘。
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration.copy() as? URLSessionConfiguration ?? configuration
        config.timeoutIntervalForRequest = ProviderSupport.defaultTimeout
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest, timeout: TimeInterval) async throws -> HTTPResponse {
        var request = request
        request.timeoutInterval = timeout > 0 ? timeout : ProviderSupport.defaultTimeout
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SpeakorbError.networkUnavailable
            }
            return HTTPResponse(data: data, statusCode: http.statusCode)
        } catch let error as URLError {
            // 超时和断网要分开报：前者让用户重试，后者提示先用本机（Errors.swift 的 userMessage）。
            if error.code == .timedOut { throw SpeakorbError.timedOut }
            throw SpeakorbError.networkUnavailable
        }
    }
}
