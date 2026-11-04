import Foundation

public protocol AudioCapturing: AnyObject {
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording() async throws -> AudioPayload
    func cancelRecording()
}

public protocol LocalTranscribing: AnyObject {
    var isAvailable: Bool { get }
    func transcribe(_ payload: AudioPayload, language: String, glossary: [DictionaryEntry]) async throws -> String
}

public protocol CloudCompleting: AnyObject {
    var id: ProviderID { get }
    func complete(audio: AudioPayload?, text: String?, prompt: String, options: ProviderOptions) async throws -> String
}

public protocol ProviderResolving: AnyObject {
    func provider(for id: ProviderID) -> CloudCompleting?
}

public protocol Injecting: AnyObject {
    func inject(_ text: String) async -> InjectionOutcome
}

public struct InjectionOutcome: Equatable, Sendable {
    public enum Method: String, Sendable {
        case paste
        case copyOnly
        case failed
    }
    public var method: Method
    public var message: String?

    public init(method: Method, message: String? = nil) {
        self.method = method
        self.message = message
    }
}

public protocol KeyStoring: AnyObject {
    func setKey(_ key: String, for provider: ProviderID) throws
    func key(for provider: ProviderID) -> String?
    func removeKey(for provider: ProviderID) throws
}

public protocol HistoryStoring: AnyObject {
    func save(_ record: TranscriptRecord) throws
    func recent(limit: Int) throws -> [TranscriptRecord]
    func delete(id: UUID) throws
    func clear() throws
}

public protocol SettingsStoring: AnyObject {
    var settings: AppSettings { get set }
    func save()
}

public protocol PermissionChecking: AnyObject {
    var microphoneGranted: Bool { get }
    var accessibilityGranted: Bool { get }
    var inputMonitoringGranted: Bool { get }
    func requestMicrophone()
    func openAccessibilitySettings()
    func openInputMonitoringSettings()
}

public protocol HotkeyMonitoring: AnyObject {
    func start(onToggle: @escaping () -> Void, onCancel: @escaping () -> Void) throws
    func stop()
    var isRunning: Bool { get }
}
