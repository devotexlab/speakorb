import XCTest
@testable import SpeakorbCore

final class FakeAudio: AudioCapturing {
    var isRecording = false
    var payload = AudioPayload(data: Data([0, 1, 2]), durationMs: 1200)
    func startRecording() throws { isRecording = true }
    func stopRecording() async throws -> AudioPayload { isRecording = false; return payload }
    func cancelRecording() { isRecording = false }
}

final class FakeLocal: LocalTranscribing {
    var isAvailable = true
    var text = "你好。"
    var lastLanguage: String?
    func transcribe(_ payload: AudioPayload, language: String, glossary: [DictionaryEntry]) async throws -> String {
        lastLanguage = language
        return text
    }
}

final class FakeProvider: CloudCompleting {
    var id: ProviderID = .gemini
    var text = "云端结果。"
    var lastPrompt: String?
    func complete(audio: AudioPayload?, text: String?, prompt: String, options: ProviderOptions) async throws -> String {
        lastPrompt = prompt
        return self.text
    }
}

final class FakeProviders: ProviderResolving {
    var providers: [ProviderID: CloudCompleting] = [:]
    func provider(for id: ProviderID) -> CloudCompleting? { providers[id] }
}

final class FakeInjector: Injecting {
    var injected: [String] = []
    var outcome = InjectionOutcome(method: .paste)
    func inject(_ text: String) async -> InjectionOutcome { injected.append(text); return outcome }
}

final class FakeKeys: KeyStoring {
    var keys: [ProviderID: String] = [:]
    func setKey(_ key: String, for provider: ProviderID) throws { keys[provider] = key }
    func key(for provider: ProviderID) -> String? { keys[provider] }
    func removeKey(for provider: ProviderID) throws { keys[provider] = nil }
}

final class FakeHistory: HistoryStoring {
    var records: [TranscriptRecord] = []
    func save(_ record: TranscriptRecord) throws { records.append(record) }
    func recent(limit: Int) throws -> [TranscriptRecord] { records }
    func delete(id: UUID) throws {}
    func clear() throws {}
}

final class FakeSettings: SettingsStoring {
    var settings: AppSettings
    init(_ settings: AppSettings = AppSettings()) { self.settings = settings }
    func save() {}
}

@MainActor
final class SessionControllerTests: XCTestCase {
    func makeController(
        settings: AppSettings = AppSettings(preferredProvider: .local, allowCloud: false),
        localAvailable: Bool = true,
        injector: FakeInjector = FakeInjector(),
        history: FakeHistory = FakeHistory(),
        keys: FakeKeys = FakeKeys(),
        providers: FakeProviders = FakeProviders()
    ) -> (SessionController, FakeLocal, FakeInjector) {
        let local = FakeLocal()
        local.isAvailable = localAvailable
        let store = FakeSettings(settings)
        let controller = SessionController(
            audio: FakeAudio(),
            local: local,
            providers: providers,
            injector: injector,
            keys: keys,
            history: history,
            settingsStore: store
        )
        return (controller, local, injector)
    }

    func testLocalDictationPostsCleanedText() async {
        let (controller, _, injector) = makeController()
        controller.begin()
        XCTAssertEqual(controller.state, .listening)
        await controller.finish()
        XCTAssertEqual(injector.injected, ["你好"])
        XCTAssertEqual(controller.state, .idle)
    }

    func testCloudUsedWhenKeyExists() async {
        let settings = AppSettings(preferredProvider: .gemini, allowCloud: true)
        let keys = FakeKeys()
        keys.keys[.gemini] = "test-key"
        let providers = FakeProviders()
        let provider = FakeProvider()
        providers.providers[.gemini] = provider
        let (controller, _, injector) = makeController(settings: settings, keys: keys, providers: providers)
        controller.begin()
        await controller.finish()
        XCTAssertEqual(injector.injected, ["云端结果"])
    }

    func testFailureWhenLocalUnavailableAndNoCloud() async {
        let (controller, _, _) = makeController(localAvailable: false)
        controller.begin()
        await controller.finish()
        if case .failed = controller.state {} else {
            XCTFail("expected failed state, got \(controller.state)")
        }
    }

    func testEnglishDictationReachesTranscriberAndKeepsPeriod() async {
        let settings = AppSettings(preferredProvider: .local, allowCloud: false, language: DictationLanguage.english.rawValue)
        let (controller, local, injector) = makeController(settings: settings)
        local.text = "See you at noon."
        controller.begin()
        await controller.finish()
        XCTAssertEqual(local.lastLanguage, "en-US")
        XCTAssertEqual(injector.injected, ["See you at noon."])
    }

    func testEnglishDictationSendsEnglishPromptToService() async {
        let settings = AppSettings(preferredProvider: .gemini, allowCloud: true, language: DictationLanguage.english.rawValue)
        let keys = FakeKeys()
        keys.keys[.gemini] = "test-key"
        let providers = FakeProviders()
        let provider = FakeProvider()
        provider.text = "Done."
        providers.providers[.gemini] = provider
        let (controller, _, injector) = makeController(settings: settings, keys: keys, providers: providers)
        controller.begin()
        await controller.finish()
        XCTAssertEqual(provider.lastPrompt?.hasPrefix("You are a dictation assistant."), true)
        XCTAssertEqual(injector.injected, ["Done."])
    }

    func testCancelReturnsToIdle() {
        let (controller, _, _) = makeController()
        controller.begin()
        controller.cancel()
        XCTAssertEqual(controller.state, .idle)
    }
}
