import Foundation
import XCTest
import SpeakorbCore
@testable import SpeakorbProviders

/// 假的网络层：记下每一次请求（含超时预算），按测试给的回应或错误返回。
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Call {
        let request: URLRequest
        let timeout: TimeInterval
    }

    private(set) var calls: [Call] = []
    var response = HTTPResponse(data: Data("{}".utf8), statusCode: 200)
    var error: Error?

    func send(_ request: URLRequest, timeout: TimeInterval) async throws -> HTTPResponse {
        calls.append(Call(request: request, timeout: timeout))
        if let error { throw error }
        return response
    }
}

private func makeAudio(container: AudioContainer = .wav) -> AudioPayload {
    AudioPayload(
        data: Data([0x52, 0x49, 0x46, 0x46, 0x01, 0x02, 0x03]),
        sampleRate: 16_000,
        channels: 1,
        container: container,
        durationMs: 1_200
    )
}

private func httpResponse(_ json: [String: Any], status: Int = 200) -> HTTPResponse {
    let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    return HTTPResponse(data: data, statusCode: status)
}

private func errorResponse(status: Int, message: String) -> HTTPResponse {
    httpResponse(["error": ["message": message]], status: status)
}

private func bodyJSON(_ call: StubTransport.Call) throws -> [String: Any] {
    let data = try XCTUnwrap(call.request.httpBody)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func temperature(_ body: [String: Any]) -> Double? {
    (body["temperature"] as? NSNumber)?.doubleValue
}

/// 调一次，断言抛的是想要的 SpeakorbError。
private func assertThrows(
    _ provider: CloudCompleting,
    audio: AudioPayload? = nil,
    text: String? = "原文",
    expected: SpeakorbError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await provider.complete(audio: audio, text: text, prompt: "系统提示", options: ProviderOptions())
        XCTFail("应当抛错，实际正常返回", file: file, line: line)
    } catch let error as SpeakorbError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("抛了别的错误：\(error)", file: file, line: line)
    }
}

private let okChoices: [String: Any] = [
    "choices": [["message": ["content": "整理后的文字"]]],
]

private let okGemini: [String: Any] = [
    "candidates": [["content": ["parts": [["text": "整理后的文字"]]], "finishReason": "STOP"]],
]

// MARK: - 工厂

final class ProviderFactoryTests: XCTestCase {
    func testStandardRegistersSixByOKEntries() {
        let registry = ProviderFactory.standard(keys: [:], custom: nil, transport: StubTransport())
        XCTAssertEqual(
            Set(registry.registeredIDs.map(\.rawValue)),
            ["gemini", "openai", "openrouter", "deepseek", "bailian", "custom"]
        )
        XCTAssertNil(registry.provider(for: .local), "本机不属于云提供方")
    }

    func testStandardWiresInjectedTransport() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let registry = ProviderFactory.standard(keys: [.openai: "sk-test"], custom: nil, transport: stub)
        let provider = try XCTUnwrap(registry.provider(for: .openai))
        let text = try await provider.complete(audio: makeAudio(), text: nil, prompt: "系统提示", options: ProviderOptions())
        XCTAssertEqual(text, "整理后的文字")
        XCTAssertEqual(stub.calls.count, 1)
    }

    func testCustomEntryWithoutSettingsRejects() async {
        let stub = StubTransport()
        let registry = ProviderFactory.standard(keys: [.custom: "custom-key"], custom: nil, transport: stub)
        let provider = try! XCTUnwrap(registry.provider(for: .custom))
        await assertThrows(provider, text: "原文", expected: .providerRejected(.custom, "还没配置自定义服务的地址和模型名"))
        XCTAssertTrue(stub.calls.isEmpty)
    }
}

// MARK: - Gemini

final class GeminiProviderTests: XCTestCase {
    func testRequestCarriesInlineBase64AndSystemPrompt() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okGemini)
        let provider = GeminiProvider(
            key: "gem-key",
            transport: stub,
            model: "gemini-test",
            baseURL: URL(string: "https://gemini.test/v1beta")!
        )

        let text = try await provider.complete(audio: makeAudio(), text: nil, prompt: "系统提示", options: ProviderOptions())
        XCTAssertEqual(text, "整理后的文字")

        let call = try XCTUnwrap(stub.calls.first)
        XCTAssertEqual(call.request.httpMethod, "POST")
        XCTAssertEqual(call.request.url?.host, "gemini.test")
        XCTAssertEqual(call.request.url?.path, "/v1beta/models/gemini-test:generateContent")
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "x-goog-api-key"), "gem-key")
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try bodyJSON(call)
        let generation = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual((generation["temperature"] as? NSNumber)?.doubleValue, 0)
        let system = try XCTUnwrap(body["systemInstruction"] as? [String: Any])
        let systemParts = try XCTUnwrap(system["parts"] as? [[String: Any]])
        XCTAssertEqual(systemParts.first?["text"] as? String, "系统提示")

        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2, "录音 + 一句提示")
        let inline = try XCTUnwrap(parts.first?["inlineData"] as? [String: Any])
        XCTAssertEqual(inline["mimeType"] as? String, "audio/wav")
        XCTAssertEqual(inline["data"] as? String, makeAudio().data.base64EncodedString())
        XCTAssertNotNil(parts.last?["text"] as? String)
    }

    func testTextOnlyRequestHasNoInlineData() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okGemini)
        let provider = GeminiProvider(key: "gem-key", transport: stub)

        _ = try await provider.complete(audio: nil, text: "本机转写的原文", prompt: "", options: ProviderOptions())
        let body = try bodyJSON(try XCTUnwrap(stub.calls.first))
        XCTAssertNil(body["systemInstruction"], "没有提示词时不带 systemInstruction")
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?["text"] as? String, "本机转写的原文")
        XCTAssertNil(parts.first?["inlineData"])
    }

    func testKeepsBaseURLWithoutDoubleSlash() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okGemini)
        let provider = GeminiProvider(
            key: "k",
            transport: stub,
            model: "m",
            baseURL: URL(string: "https://gemini.test/v1beta/")!
        )
        _ = try await provider.complete(audio: makeAudio(), text: nil, prompt: "", options: ProviderOptions())
        XCTAssertEqual(stub.calls.first?.request.url?.absoluteString, "https://gemini.test/v1beta/models/m:generateContent")
    }
}

// MARK: - OpenAI

final class OpenAIProviderTests: XCTestCase {
    func testAudioRequestShape() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = OpenAIProvider(
            key: "sk-test",
            transport: stub,
            model: "gpt-audio-mini-test",
            baseURL: URL(string: "https://openai.test/v1")!
        )

        let text = try await provider.complete(audio: makeAudio(), text: nil, prompt: "系统提示", options: ProviderOptions())
        XCTAssertEqual(text, "整理后的文字")

        let call = try XCTUnwrap(stub.calls.first)
        XCTAssertEqual(call.request.url?.absoluteString, "https://openai.test/v1/chat/completions")
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let body = try bodyJSON(call)
        XCTAssertEqual(body["model"] as? String, "gpt-audio-mini-test")
        XCTAssertEqual(temperature(body), 0)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "系统提示")
        let user = try XCTUnwrap(messages.last)
        XCTAssertEqual(user["role"] as? String, "user")
        let content = try XCTUnwrap(user["content"] as? [[String: Any]])
        let audioPart = try XCTUnwrap(content.first)
        XCTAssertEqual(audioPart["type"] as? String, "input_audio")
        let payload = try XCTUnwrap(audioPart["input_audio"] as? [String: Any])
        XCTAssertEqual(payload["format"] as? String, "wav")
        XCTAssertEqual(payload["data"] as? String, makeAudio().data.base64EncodedString())
        XCTAssertEqual(content.last?["type"] as? String, "text")
    }

    func testTextOnlyRequestSendsPlainUserContent() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = OpenAIProvider(key: "sk-test", transport: stub)

        _ = try await provider.complete(audio: nil, text: "本机转写原文", prompt: "系统提示", options: ProviderOptions())

        let body = try bodyJSON(try XCTUnwrap(stub.calls.first))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?["content"] as? String, "本机转写原文")
    }

    func testEmptyContentRejected() async {
        let stub = StubTransport()
        stub.response = httpResponse(["choices": [["message": ["content": "   "]]]])
        let provider = OpenAIProvider(key: "sk-test", transport: stub)
        await assertThrows(provider, expected: .providerRejected(.openai, "模型没有返回文字"))
    }

    func testContentFilterRejected() async {
        let stub = StubTransport()
        stub.response = httpResponse(["choices": [["finish_reason": "content_filter", "message": ["content": "x"]]]])
        let provider = OpenAIProvider(key: "sk-test", transport: stub)
        await assertThrows(provider, expected: .providerRejected(.openai, "内容被拦下（content_filter）"))
    }

    func testMissingChoicesRejected() async {
        let stub = StubTransport()
        stub.response = httpResponse([:])
        let provider = OpenAIProvider(key: "sk-test", transport: stub)
        await assertThrows(provider, expected: .providerRejected(.openai, "响应里没有 choices"))
    }

    func testNonJSONSuccessBodyRejected() async {
        let stub = StubTransport()
        stub.response = HTTPResponse(data: Data("not json".utf8), statusCode: 200)
        let provider = OpenAIProvider(key: "sk-test", transport: stub)
        await assertThrows(provider, expected: .providerRejected(.openai, "响应不是 JSON"))
    }
}

// MARK: - OpenRouter / DeepSeek / 百炼 / 自定义

final class OpenRouterProviderTests: XCTestCase {
    func testAudioGoesThroughInputAudio() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = OpenRouterProvider(
            key: "or-key",
            transport: stub,
            model: "openai/gpt-audio-mini",
            baseURL: URL(string: "https://openrouter.test/api/v1")!
        )
        _ = try await provider.complete(audio: makeAudio(), text: nil, prompt: "系统提示", options: ProviderOptions())

        let call = try XCTUnwrap(stub.calls.first)
        XCTAssertEqual(call.request.url?.absoluteString, "https://openrouter.test/api/v1/chat/completions")
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "HTTP-Referer"), ProviderDefaults.openRouterReferer)
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "X-Title"), "Speakorb")
        let body = try bodyJSON(call)
        XCTAssertEqual(body["model"] as? String, "openai/gpt-audio-mini")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_audio")
    }

    func testTextOnlyUsesPlainContent() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = OpenRouterProvider(key: "or-key", transport: stub)
        _ = try await provider.complete(audio: nil, text: "原文", prompt: "提示", options: ProviderOptions())
        let body = try bodyJSON(try XCTUnwrap(stub.calls.first))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.last?["content"] as? String, "原文")
    }
}

final class DeepSeekProviderTests: XCTestCase {
    func testRefusesAudioWithoutSendingRequest() async {
        let stub = StubTransport()
        let provider = DeepSeekProvider(key: "ds-key", transport: stub, baseURL: URL(string: "https://deepseek.test/v1")!)
        await assertThrows(
            provider,
            audio: makeAudio(),
            text: nil,
            expected: .providerRejected(.deepseek, "这家只做文字整理，要先把录音在本机转成文字")
        )
        XCTAssertTrue(stub.calls.isEmpty, "不该发一个注定 400 的请求")
    }

    func testTextPolishRequest() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = DeepSeekProvider(
            key: "ds-key",
            transport: stub,
            model: "deepseek-flash-test",
            baseURL: URL(string: "https://deepseek.test/v1")!
        )
        let text = try await provider.complete(audio: nil, text: "本机转写原文", prompt: "系统提示", options: ProviderOptions())
        XCTAssertEqual(text, "整理后的文字")

        let call = try XCTUnwrap(stub.calls.first)
        XCTAssertEqual(call.request.url?.absoluteString, "https://deepseek.test/v1/chat/completions")
        let body = try bodyJSON(call)
        XCTAssertEqual(body["model"] as? String, "deepseek-flash-test")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["content"] as? String, "系统提示")
        XCTAssertEqual(messages.last?["content"] as? String, "本机转写原文")
    }
}

final class BailianProviderTests: XCTestCase {
    func testAudioUsesDataURIAndTextModality() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = BailianProvider(
            key: "bl-key",
            transport: stub,
            model: "qwen3.8-omni-flash",
            baseURL: URL(string: "https://bailian.test/compatible-mode/v1")!
        )
        _ = try await provider.complete(audio: makeAudio(), text: nil, prompt: "系统提示", options: ProviderOptions())

        let call = try XCTUnwrap(stub.calls.first)
        XCTAssertEqual(call.request.url?.absoluteString, "https://bailian.test/compatible-mode/v1/chat/completions")
        let body = try bodyJSON(call)
        XCTAssertEqual(body["modalities"] as? [String], ["text"])
        XCTAssertEqual((body["enable_thinking"] as? NSNumber)?.boolValue, false)

        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        let payload = try XCTUnwrap(content.first?["input_audio"] as? [String: Any])
        let data = try XCTUnwrap(payload["data"] as? String)
        XCTAssertTrue(data.hasPrefix("data:audio/wav;base64,"), "百炼要 data URI：\(data.prefix(32))")
        XCTAssertEqual(payload["format"] as? String, "wav")
    }
}

final class CustomProviderTests: XCTestCase {
    func testUsesConfiguredBaseURLAndModel() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let settings = CustomProviderSettings(baseURL: URL(string: "https://custom.test/v1")!, model: "my-model")
        let provider = CustomProvider(key: "custom-key", settings: settings, transport: stub)

        let text = try await provider.complete(audio: makeAudio(), text: nil, prompt: "系统提示", options: ProviderOptions())
        XCTAssertEqual(text, "整理后的文字")

        let call = try XCTUnwrap(stub.calls.first)
        XCTAssertEqual(call.request.url?.absoluteString, "https://custom.test/v1/chat/completions")
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "Authorization"), "Bearer custom-key")
        let body = try bodyJSON(call)
        XCTAssertEqual(body["model"] as? String, "my-model")
    }

    func testMissingSettingsRejected() async {
        let stub = StubTransport()
        let provider = CustomProvider(key: "custom-key", settings: nil, transport: stub)
        await assertThrows(provider, expected: .providerRejected(.custom, "还没配置自定义服务的地址和模型名"))
        XCTAssertTrue(stub.calls.isEmpty)
    }
}

// MARK: - 错误映射与超时

final class ProviderErrorMappingTests: XCTestCase {
    func testUnauthorizedMapsToInvalidKey() async {
        for status in [401, 403] {
            let stub = StubTransport()
            stub.response = errorResponse(status: status, message: "bad key")
            let provider = OpenAIProvider(key: "sk-test", transport: stub)
            await assertThrows(provider, expected: .invalidAPIKey(.openai))
        }
    }

    func testRateLimitAndServerErrorsMapToRejected() async {
        for (status, message) in [(429, "rate limited"), (500, "server error"), (503, "unavailable")] {
            let stub = StubTransport()
            stub.response = errorResponse(status: status, message: message)
            let provider = GeminiProvider(key: "k", transport: stub)
            await assertThrows(provider, expected: .providerRejected(.gemini, message))
        }
    }

    func testBadRequestMapsToRejectedWithUpstreamMessage() async {
        let stub = StubTransport()
        stub.response = errorResponse(status: 400, message: "model not found")
        let provider = BailianProvider(key: "bl-key", transport: stub)
        await assertThrows(provider, expected: .providerRejected(.bailian, "model not found"))
    }

    func testTransportErrorsMapToNetworkAndTimeout() async {
        let networkStub = StubTransport()
        networkStub.error = URLError(.notConnectedToInternet)
        let networkProvider = OpenAIProvider(key: "sk-test", transport: networkStub)
        await assertThrows(networkProvider, expected: .networkUnavailable)

        let timeoutStub = StubTransport()
        timeoutStub.error = URLError(.timedOut)
        let timeoutProvider = OpenAIProvider(key: "sk-test", transport: timeoutStub)
        await assertThrows(timeoutProvider, expected: .timedOut)
    }

    func testMissingKeyThrowsBeforeAnyRequest() async {
        let stub = StubTransport()
        let provider = OpenAIProvider(key: nil, transport: stub)
        await assertThrows(provider, expected: .missingAPIKey(.openai))
        XCTAssertTrue(stub.calls.isEmpty)

        let blank = StubTransport()
        let blankProvider = GeminiProvider(key: "   ", transport: blank)
        await assertThrows(blankProvider, expected: .missingAPIKey(.gemini))
        XCTAssertTrue(blank.calls.isEmpty)
    }

    func testDefaultTimeoutIs25Seconds() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = OpenAIProvider(key: "sk-test", transport: stub)
        _ = try await provider.complete(audio: makeAudio(), text: nil, prompt: "提示", options: ProviderOptions())
        XCTAssertEqual(stub.calls.first?.timeout, 25)
    }

    func testCustomTimeoutIsForwarded() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = OpenAIProvider(key: "sk-test", transport: stub)
        _ = try await provider.complete(
            audio: makeAudio(),
            text: nil,
            prompt: "提示",
            options: ProviderOptions(timeout: 12)
        )
        XCTAssertEqual(stub.calls.first?.timeout, 12)
    }

    func testZeroTimeoutFallsBackTo25() async throws {
        let stub = StubTransport()
        stub.response = httpResponse(okChoices)
        let provider = OpenAIProvider(key: "sk-test", transport: stub)
        _ = try await provider.complete(
            audio: makeAudio(),
            text: nil,
            prompt: "提示",
            options: ProviderOptions(timeout: 0)
        )
        XCTAssertEqual(stub.calls.first?.timeout, 25)
    }
}
