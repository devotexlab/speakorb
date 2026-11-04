import Foundation

public enum SpeakorbError: Error, Equatable, Sendable {
    case microphonePermission
    case accessibilityPermission
    case inputMonitoringPermission
    case recordingFailed(String)
    case emptyRecording
    case noSpeech
    case localModelUnavailable
    case missingAPIKey(ProviderID)
    case invalidAPIKey(ProviderID)
    case providerRejected(ProviderID, String)
    case networkUnavailable
    case timedOut
    case injectionFailed(String)
    case keychainFailed(String)
    case storageFailed(String)

    public var code: String {
        switch self {
        case .microphonePermission, .accessibilityPermission, .inputMonitoringPermission: return "PERMISSION"
        case .recordingFailed: return "RECORDING_FAILED"
        case .emptyRecording: return "EMPTY_RECORDING"
        case .noSpeech: return "NO_SPEECH"
        case .localModelUnavailable: return "LOCAL_MODEL_UNAVAILABLE"
        case .missingAPIKey: return "MISSING_KEY"
        case .invalidAPIKey: return "INVALID_KEY"
        case .providerRejected: return "PROVIDER_REJECTED"
        case .networkUnavailable: return "NETWORK"
        case .timedOut: return "TIMEOUT"
        case .injectionFailed: return "INJECTION_FAILED"
        case .keychainFailed: return "KEYCHAIN"
        case .storageFailed: return "STORAGE"
        }
    }

    /// 面向用户的提示：不出现"模型/API/密钥/token"等技术词（UI 规范）。
    public var userMessage: String {
        switch self {
        case .microphonePermission: return "需要麦克风才能听清你说话"
        case .accessibilityPermission: return "需要开启辅助功能才能把字放进输入框"
        case .inputMonitoringPermission: return "需要开启输入监控才能用快捷键"
        case .recordingFailed: return "录音没开始，再试一次"
        case .emptyRecording: return "没录到声音，检查麦克风"
        case .noSpeech: return "没听到声音，再说一次"
        case .localModelUnavailable: return "本机听写还没准备好"
        case .missingAPIKey: return "还没接入你的账号"
        case .invalidAPIKey: return "这把钥匙好像不对，换一把试试"
        case .providerRejected: return "服务暂时用不了，先试试本机"
        case .networkUnavailable: return "网络不太好，先用本机"
        case .timedOut: return "这次有点慢，再试一次"
        case .injectionFailed: return "这段已复制，手动粘贴一下"
        case .keychainFailed: return "保存失败，稍后再试"
        case .storageFailed: return "记录保存失败"
        }
    }

    public var recovery: String? {
        switch self {
        case .microphonePermission, .accessibilityPermission, .inputMonitoringPermission: return "去开启"
        case .invalidAPIKey, .missingAPIKey: return "去设置"
        case .noSpeech, .emptyRecording: return "重说"
        case .timedOut, .networkUnavailable: return "重试"
        default: return nil
        }
    }
}
