import Foundation

@MainActor
public final class SessionController {
    public enum State: Equatable {
        case idle
        case listening
        case transcribing
        case injecting
        case failed(SpeakorbError)
    }

    public private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    public var onStateChange: ((State) -> Void)?
    public var onText: ((TranscriptRecord) -> Void)?
    public var onFailure: ((SpeakorbError) -> Void)?

    private let audio: AudioCapturing
    private let local: LocalTranscribing
    private let providers: ProviderResolving
    private let injector: Injecting
    private let keys: KeyStoring
    private let history: HistoryStoring
    private let settingsStore: SettingsStoring
    private let router = Router()
    private let refiner = Refiner()
    private let glossary = Glossary()

    public private(set) var consecutiveFailures = 0

    public init(
        audio: AudioCapturing,
        local: LocalTranscribing,
        providers: ProviderResolving,
        injector: Injecting,
        keys: KeyStoring,
        history: HistoryStoring,
        settingsStore: SettingsStoring
    ) {
        self.audio = audio
        self.local = local
        self.providers = providers
        self.injector = injector
        self.keys = keys
        self.history = history
        self.settingsStore = settingsStore
    }

    public func toggle() async {
        switch state {
        case .idle, .failed:
            begin()
        case .listening:
            await finish()
        case .transcribing, .injecting:
            break
        }
    }

    public func begin() {
        guard state == .idle || isFailed else { return }
        do {
            try audio.startRecording()
            state = .listening
        } catch {
            fail(.recordingFailed("\(error)"))
        }
    }

    public func cancel() {
        guard state == .listening else { return }
        audio.cancelRecording()
        state = .idle
    }

    public func finish() async {
        guard state == .listening else { return }
        state = .transcribing
        let started = Date()
        do {
            let payload = try await audio.stopRecording()
            guard payload.durationMs >= 300 else { throw SpeakorbError.emptyRecording }
            let settings = settingsStore.settings
            let prompt = refiner.prompt(language: settings.language, glossary: settings.dictionary)
            let text = try await transcribe(payload, settings: settings, prompt: prompt)
            let cleaned = refiner.postProcess(text, language: settings.language)
            guard !cleaned.isEmpty else { throw SpeakorbError.noSpeech }

            state = .injecting
            let outcome = await injector.inject(cleaned)
            if outcome.method == .failed {
                throw SpeakorbError.injectionFailed(outcome.message ?? "")
            }
            if outcome.method == .copyOnly {
                throw SpeakorbError.injectionFailed(outcome.message ?? "copied")
            }
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            let record = TranscriptRecord(text: cleaned, provider: settings.preferredProvider, route: .local, durationMs: payload.durationMs, latencyMs: latency)
            try? history.save(record)
            consecutiveFailures = 0
            onText?(record)
            state = .idle
        } catch let error as SpeakorbError {
            consecutiveFailures += 1
            fail(error)
        } catch {
            consecutiveFailures += 1
            fail(.recordingFailed("\(error)"))
        }
    }

    private func transcribe(_ payload: AudioPayload, settings: AppSettings, prompt: String) async throws -> String {
        let decision = router.decide(
            preferred: settings.preferredProvider,
            allowCloud: settings.allowCloud,
            hasKey: { [keys] id in keys.key(for: id) != nil },
            localAvailable: local.isAvailable,
            networkAvailable: true,
            consecutiveFailures: consecutiveFailures
        )
        switch decision {
        case .local:
            return try await local.transcribe(payload, language: settings.language, glossary: settings.dictionary)
        case let .cloud(id, mode):
            guard let provider = providers.provider(for: id) else { throw SpeakorbError.providerRejected(id, "no provider") }
            let options = ProviderOptions(language: settings.language, glossary: settings.dictionary)
            do {
                if mode == .polish {
                    let base = try await local.transcribe(payload, language: settings.language, glossary: options.glossary)
                    return try await provider.complete(audio: nil, text: base, prompt: prompt, options: options)
                }
                return try await provider.complete(audio: payload, text: nil, prompt: prompt, options: options)
            } catch {
                if local.isAvailable {
                    return try await local.transcribe(payload, language: settings.language, glossary: options.glossary)
                }
                throw SpeakorbError.providerRejected(id, "\(error)")
            }
        case .unavailable(let err):
            throw err
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func fail(_ error: SpeakorbError) {
        state = .failed(error)
        onFailure?(error)
    }
}

