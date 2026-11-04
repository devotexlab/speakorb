import AppKit
import Foundation
import Speech
import SpeakorbCore

/// 系统听写：SFSpeechRecognizer；有离线包时强制 on-device，没有时退回在线听写。
///
/// 约定：
/// - 只接受 16 kHz 单声道 WAV（AudioRecorder 的交付格式），先落临时文件再走 SFSpeechURLRecognitionRequest；
/// - isAvailable 以系统 recognizer 存在为准；离线能力单独用 onDeviceAvailable 暴露；授权在 transcribe 里按需请求；
/// - 20 s 超时（SFSpeechRecognitionTask 无法直接 await，用 continuation + 定时器实现）；
/// - 错误映射：无语音→noSpeech、未授权/能力不可用→localModelUnavailable、超时→timedOut。
public final class SpeechTranscriber: LocalTranscribing, @unchecked Sendable {
    public static let defaultLocaleIdentifier = "zh-CN"
    public static let defaultTimeout: TimeInterval = 20

    private let timeout: TimeInterval
    private let fileManager: FileManager
    private let lock = NSLock()
    private var currentLanguage = SpeechTranscriber.defaultLocaleIdentifier

    /// 你说哪种话（AppSettings.language）。只影响下面两个“能不能用”的判断；
    /// 真正听写时用 transcribe 传进来的语言。
    public var language: String {
        get { lock.lock(); defer { lock.unlock() }; return currentLanguage }
        set { lock.lock(); currentLanguage = Self.localeIdentifier(for: newValue); lock.unlock() }
    }

    public init(timeout: TimeInterval = SpeechTranscriber.defaultTimeout, fileManager: FileManager = .default) {
        self.timeout = max(1, timeout)
        self.fileManager = fileManager
    }

    /// 系统听写能力：权限没被拒 + 当前语言有 recognizer。
    /// 没有离线包时会退回 Apple 在线听写（仍可用，但音频可能离开本机）。
    public var isAvailable: Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted:
            return false
        case .authorized, .notDetermined:
            break
        @unknown default:
            return false
        }
        return SFSpeechRecognizer(locale: Locale(identifier: language)) != nil
    }

    /// 当前语言是否有真正的离线识别包；没有时系统听写需要联网。
    public var onDeviceAvailable: Bool {
        SFSpeechRecognizer(locale: Locale(identifier: language))?.supportsOnDeviceRecognition == true
    }

    // MARK: - LocalTranscribing

    public func transcribe(
        _ payload: AudioPayload,
        language: String,
        glossary: [DictionaryEntry]
    ) async throws -> String {
        guard payload.container == .wav, !payload.data.isEmpty else {
            throw SpeakorbError.localModelUnavailable
        }

        try await ensureAuthorization()

        let identifier = Self.localeIdentifier(for: language)
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)) else {
            throw SpeakorbError.localModelUnavailable
        }
        let audioURL = try writeTemporaryFile(payload.data)
        defer { try? fileManager.removeItem(at: audioURL) }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        // 有离线包就强制离线；没有则允许系统在线听写（仍然零配置可用）。
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        let terms = glossary
            .map { $0.term.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !terms.isEmpty {
            request.contextualStrings = terms
        }

        let text = try await recognize(recognizer: recognizer, request: request)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeakorbError.noSpeech
        }
        return trimmed
    }

    // MARK: - 识别

    private func recognize(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let gate = RecognitionGate(continuation: continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    gate.fail(Self.map(error))
                    return
                }
                guard let result, result.isFinal else { return }
                gate.succeed(result.bestTranscription.formattedString)
            }
            gate.attach(task)
            gate.scheduleTimeout(after: timeout)
        }
    }

    private func ensureAuthorization() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard status == .authorized else {
                throw SpeakorbError.localModelUnavailable
            }
        case .denied, .restricted:
            throw SpeakorbError.localModelUnavailable
        @unknown default:
            throw SpeakorbError.localModelUnavailable
        }
    }

    // MARK: - 工具

    /// "zh" → "zh-CN"、"en" → "en-US"；带地区的原样（下划线换成横线）。
    public static func localeIdentifier(for language: String) -> String {
        let raw = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return defaultLocaleIdentifier }
        if raw.contains("-") || raw.contains("_") {
            return raw.replacingOccurrences(of: "_", with: "-")
        }
        switch raw.lowercased() {
        case "zh": return "zh-CN"
        case "en": return "en-US"
        default: return raw
        }
    }

    /// 把 WAV 写到临时目录，识别完立即删。
    private func writeTemporaryFile(_ data: Data) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("speakorb-asr-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw SpeakorbError.localModelUnavailable
        }
        return url
    }

    /// SFSpeechRecognizer 的错误域/码 → SpeakorbError；未知错误按本机听写不可用处理（不把技术细节抛给用户）。
    public static func map(_ error: Error) -> SpeakorbError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return .timedOut
        }
        if nsError.domain == "kAFAssistantErrorDomain" {
            switch nsError.code {
            case 1110: // 没有检测到语音
                return .noSpeech
            case 1101: // 未授权
                return .localModelUnavailable
            default:
                return .localModelUnavailable
            }
        }
        return .localModelUnavailable
    }
}


public extension SpeechTranscriber {
    /// 当前系统听写授权状态（给权限向导显示用）。
    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// 请求系统听写授权；已经决定过时直接返回当前结果（不会重复弹窗）。
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            return status == .authorized
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// 打开系统设置里的「语音识别」页（权限被拒时给用户一个下一步）。
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// 保证 continuation 只被 resume 一次；超时会取消底层 SFSpeechRecognitionTask。
private final class RecognitionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var finished = false

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func attach(_ task: SFSpeechRecognitionTask) {
        lock.lock()
        let alreadyFinished = finished
        if !alreadyFinished {
            self.task = task
        }
        lock.unlock()
        if alreadyFinished {
            task.cancel()
        }
    }

    func scheduleTimeout(after seconds: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.finish(.failure(SpeakorbError.timedOut), cancelTask: true)
        }
    }

    func succeed(_ text: String) {
        finish(.success(text), cancelTask: false)
    }

    func fail(_ error: Error) {
        finish(.failure(error), cancelTask: false)
    }

    private func finish(_ result: Result<String, Error>, cancelTask: Bool) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        self.task = nil
        lock.unlock()

        if cancelTask {
            task?.cancel()
        }
        switch result {
        case let .success(text):
            continuation?.resume(returning: text)
        case let .failure(error):
            continuation?.resume(throwing: error)
        }
    }
}
