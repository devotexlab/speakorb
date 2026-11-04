import Foundation
import SwiftUI
import SpeakorbCore

/// 界面语言：默认英文，可在第一屏或「设置 → 通用」里换成中文。和听写语言无关。
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    /// 每种语言用自己的文字显示自己，切换时谁都认得。
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    var locale: Locale {
        Locale(identifier: self == .chinese ? "zh_CN" : "en_US")
    }
}

enum L10n {
    /// 当前界面语言。只在主线程改（AppModel.language），读的地方都是界面代码。
    nonisolated(unsafe) static var current: AppLanguage = .english
}

/// 同一句话的英文和中文写在一起，按当前界面语言取一句。
func tr(_ english: String, _ chinese: String) -> String {
    L10n.current == .chinese ? chinese : english
}

extension SpeakorbError {
    /// 界面上显示的那句话（中文沿用 Core 里的文案）。
    var localizedMessage: String {
        guard L10n.current == .english else { return userMessage }
        switch self {
        case .microphonePermission: return "Turn on the microphone so Speakorb can hear you"
        case .accessibilityPermission: return "Turn on Accessibility so Speakorb can put text into fields"
        case .inputMonitoringPermission: return "Turn on Input Monitoring so the talk key works"
        case .recordingFailed: return "Recording didn't start. Try again"
        case .emptyRecording: return "No sound was recorded. Check your microphone"
        case .noSpeech: return "Didn't hear anything. Try saying it again"
        case .localModelUnavailable: return "On-device dictation isn't ready yet"
        case .missingAPIKey: return "You haven't connected that service yet"
        case .invalidAPIKey: return "That key doesn't seem right. Try another one"
        case .providerRejected: return "That service isn't available right now. Try on-device dictation"
        case .networkUnavailable: return "The connection is weak, so on-device dictation was used"
        case .timedOut: return "That took too long. Try again"
        case .injectionFailed: return "Copied. Paste it with ⌘V"
        case .keychainFailed: return "Couldn't save. Try again in a moment"
        case .storageFailed: return "Couldn't save this to History"
        }
    }
}

extension AppLanguage {
    /// 第一次用时，听写语言跟着界面语言走。
    var defaultDictation: DictationLanguage { self == .chinese ? .chinese : .english }
}

extension DictationLanguage {
    var displayName: String {
        switch self {
        case .chinese: return tr("Chinese (Mandarin)", "中文（普通话）")
        case .english: return tr("English", "英文")
        }
    }

    /// 选择器上的短名字，用它自己的文字写。
    var shortName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var detail: String {
        switch self {
        case .chinese: return tr("English words mixed in are kept as English", "中英混说会自动识别，不用切换")
        case .english: return tr("Chinese won't be recognized in this mode", "这时说中文认不出来")
        }
    }
}

/// 听写语言选择：English / 中文。设置页和第一次试说时都用它。
struct DictationLanguagePicker: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Picker("", selection: $model.dictationLanguage) {
            ForEach([DictationLanguage.english, .chinese], id: \.self) { Text($0.shortName).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(tr("Dictation language", "听写语言"))
    }
}
