import Foundation
import SwiftUI
import SpeakorbCore
import SpeakorbCapture

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel(dependencies: AppDependencies.live())

    /// 主窗口左侧的几项。
    enum Section: Hashable {
        case records
        case terms
        case settings(SettingsPage)
        case help
    }

    enum SettingsPage: String, CaseIterable, Identifiable {
        case general, cloud, local, privacy, about
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return tr("General", "通用")
            case .cloud: return tr("Better accuracy", "更准的听写")
            case .local: return tr("On-device dictation", "本机听写")
            case .privacy: return tr("Privacy", "隐私")
            case .about: return tr("About", "关于")
            }
        }
    }

    /// 悬浮条现在该显示什么；nil = 收起。
    enum HUDPhase: Equatable {
        case listening
        case writing
        case done
        case error(SpeakorbError)
    }

    @Published private(set) var state: SessionController.State = .idle
    @Published private(set) var lastError: SpeakorbError?
    @Published private(set) var lastText: String = ""
    @Published private(set) var history: [TranscriptRecord] = []
    @Published private(set) var configuredProviders: Set<ProviderID> = []
    @Published var settings: AppSettings {
        didSet {
            settingsStore.settings = settings
            if oldValue.language != settings.language {
                speech?.language = settings.language
            }
            if oldValue.launchAtLogin != settings.launchAtLogin {
                LaunchAtLogin.set(settings.launchAtLogin)
            }
        }
    }
    @Published var onboardingComplete: Bool = UserDefaults.standard.bool(forKey: Keys.onboarded)
    @Published var theme: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Keys.theme) ?? "") ?? .daylight {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }
    /// 界面语言，默认英文。改了以后整个界面马上换（RootView 用它做 id）。
    @Published var language: AppLanguage = AppModel.storedLanguage {
        didSet {
            L10n.current = language
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
        }
    }
    @Published var showInDock: Bool = UserDefaults.standard.object(forKey: Keys.dock) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showInDock, forKey: Keys.dock) }
    }
    /// 暂停时按说话键不录音。
    @Published var paused = false
    @Published var section: Section = .records
    @Published var bannerDismissed = false
    @Published private(set) var hud: HUDPhase?
    /// 当前音量 0…1（只在听的时候更新）。
    @Published private(set) var level: Double = 0
    @Published private(set) var listeningStartedAt: Date?

    private enum Keys {
        static let onboarded = "speakorb.onboarded"
        static let theme = "speakorb.theme"
        static let dock = "speakorb.showInDock"
        static let language = "speakorb.language"
    }

    private static var storedLanguage: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: Keys.language) ?? "") ?? .english
    }

    let permissions: PermissionChecking
    private let local: LocalTranscribing
    private let speech: SpeechTranscriber?
    private let recorder: AudioRecorder?
    private let controller: SessionController
    private let keys: KeyStoring
    private let historyStore: HistoryStoring
    private let settingsStore: SettingsStoring
    private let hotkey: HotkeyMonitoring
    private let providers: ProviderResolving
    private var started = false
    private var hotkeyRetry: Task<Void, Never>?
    private var levelTimer: Timer?
    private var hudHide: Task<Void, Never>?
    @Published private(set) var refreshTick = 0

    init(dependencies: AppDependencies) {
        self.permissions = dependencies.permissions
        self.local = dependencies.local
        self.speech = dependencies.local as? SpeechTranscriber
        self.recorder = dependencies.audio as? AudioRecorder
        self.keys = dependencies.keys
        self.historyStore = dependencies.history
        self.settingsStore = dependencies.settings
        self.hotkey = dependencies.hotkey
        self.providers = dependencies.providers
        self.settings = dependencies.settings.settings
        L10n.current = AppModel.storedLanguage
        (dependencies.local as? SpeechTranscriber)?.language = dependencies.settings.settings.language
        self.controller = SessionController(
            audio: dependencies.audio,
            local: dependencies.local,
            providers: dependencies.providers,
            injector: dependencies.injector,
            keys: dependencies.keys,
            history: dependencies.history,
            settingsStore: dependencies.settings
        )
        controller.onStateChange = { [weak self] state in
            self?.apply(state)
        }
        controller.onText = { [weak self] record in
            self?.lastText = record.text
            self?.lastError = nil
            self?.reloadHistory()
        }
        controller.onFailure = { [weak self] error in
            self?.lastError = error
        }
        refreshKeys()
        reloadHistory()
    }

    func start() {
        guard !started else { return }
        started = true
        attemptHotkey()
        // 用户可能在 App 启动后才开权限；每 2 秒重试一次，最多 40 秒。
        hotkeyRetry = Task { [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                if self.hotkey.isRunning { return }
                self.attemptHotkey()
            }
        }
    }

    private func attemptHotkey() {
        do {
            try hotkey.start(onToggle: { [weak self] in
                Task { @MainActor in await self?.toggle() }
            }, onCancel: { [weak self] in
                Task { @MainActor in self?.cancel() }
            })
            if hotkey.isRunning { lastError = nil }
        } catch {
            if !hotkey.isRunning { lastError = .inputMonitoringPermission }
        }
    }

    func refreshStatus() {
        refreshKeys()
        reloadHistory()
        speechGranted = speech?.isAvailable == true || SpeechTranscriber.authorizationStatus == .authorized
        if !hotkey.isRunning { attemptHotkey() }
        refreshTick += 1
    }

    /// 你说哪种话；给设置页的选择器绑定用。
    var dictationLanguage: DictationLanguage {
        get { DictationLanguage(code: settings.language) }
        set { settings.language = newValue.rawValue }
    }

    var localASRAvailable: Bool { local.isAvailable }
    var offlineAvailable: Bool { speech?.onDeviceAvailable == true }

    /// 本机听写的录音去哪：只有装了听写语言的离线包才真的不出这台 Mac；没装时系统听写会交给 Apple。
    var localPrivacyShort: String {
        offlineAvailable ? tr("Stays on this Mac", "说的话不离开这台 Mac") : tr("Apple processes audio online", "联网时由 Apple 处理录音")
    }

    var localPrivacyLine: String {
        offlineAvailable
            ? tr("With on-device dictation, what you say never leaves this Mac.", "用本机听写时，你说的话不会离开这台 Mac。")
            : tr("With on-device dictation and no offline language pack, macOS sends audio to Apple. Install the pack and it stays on this Mac.", "用本机听写时，没装离线语言包的话，系统会把录音交给 Apple 处理；装上后就不出这台 Mac。")
    }

    struct CheckItem: Identifiable {
        let id = UUID()
        /// 不随界面语言变化的英文名，写进“复制错误信息”。
        let code: String
        let title: String
        let ok: Bool
        let hint: String
    }

    var diagnostics: [CheckItem] {
        [
            CheckItem(code: "microphone", title: tr("Microphone", "麦克风"), ok: permissions.microphoneGranted, hint: tr("System Settings → Privacy & Security → Microphone", "系统设置 → 隐私与安全性 → 麦克风")),
            CheckItem(code: "accessibility", title: tr("Accessibility", "辅助功能"), ok: permissions.accessibilityGranted, hint: tr("System Settings → Privacy & Security → Accessibility", "系统设置 → 隐私与安全性 → 辅助功能")),
            CheckItem(code: "input-monitoring", title: tr("Input Monitoring", "输入监控"), ok: permissions.inputMonitoringGranted, hint: tr("System Settings → Privacy & Security → Input Monitoring", "系统设置 → 隐私与安全性 → 输入监控")),
            CheckItem(code: "speech-recognition", title: tr("Speech Recognition", "语音识别"), ok: speechGranted, hint: tr("System Settings → Privacy & Security → Speech Recognition", "系统设置 → 隐私与安全性 → 语音识别")),
            CheckItem(code: "on-device-dictation", title: tr("On-device dictation", "本机听写"), ok: localASRAvailable, hint: tr("If it's unavailable, connect a service instead", "不能用时，接入一个服务也能听写")),
            CheckItem(code: "offline-pack", title: tr("Works offline", "断网也能听写"), ok: offlineAvailable, hint: tr("Offline pack not installed; works while online", "还没装离线语言包；联网时照常能用")),
            CheckItem(code: "connected-service", title: tr("Connected service (optional)", "接入的服务（可选）"), ok: !configuredProviders.isEmpty, hint: tr("Improves accuracy", "接了字会更准")),
        ]
    }

    /// 缺了会让听写用不了的开关。
    var missingSwitch: (title: String, detail: String, open: () -> Void)? {
        if !permissions.microphoneGranted {
            return (tr("Microphone is off", "“麦克风”还没打开"), tr("Speakorb can't hear you.", "听不见你说话。"), { [weak self] in self?.permissions.requestMicrophone() })
        }
        if !permissions.inputMonitoringGranted {
            return (tr("Input Monitoring is off", "“输入监控”还没打开"), tr("Right ⌥ won't respond; for now you can only start from this window.", "按右 ⌥ 没反应；现在只能在窗口里点按钮说。"), { [weak self] in self?.openInputMonitoring() })
        }
        if !permissions.accessibilityGranted {
            return (tr("Accessibility is off", "“辅助功能”被关掉了"), tr("Your words are ready but can't be put into fields; for now they're copied instead.", "说的话写好了，但放不进输入框；现在只能复制给你。"), { [weak self] in self?.openAccessibility() })
        }
        return nil
    }

    // MARK: - 听写

    func toggle() async {
        if paused && state == .idle { return }
        await controller.toggle()
    }

    func cancel() {
        if case .error = hud { dismissHUD() }
        controller.cancel()
    }

    func dismissHUD() {
        hudHide?.cancel()
        hud = nil
    }

    private func apply(_ newState: SessionController.State) {
        let previous = state
        state = newState
        hudHide?.cancel()
        switch newState {
        case .listening:
            listeningStartedAt = Date()
            hud = .listening
            startLevelMeter()
        case .transcribing, .injecting:
            stopLevelMeter()
            hud = .writing
        case .failed(let error):
            stopLevelMeter()
            hud = .error(error)
            // “已复制”这种不算失败，6 秒后自己收起；其他没成的等用户处理。
            if case .injectionFailed = error { hideHUD(after: 6) }
        case .idle:
            stopLevelMeter()
            if previous == .injecting || previous == .transcribing {
                hud = .done
                hideHUD(after: 1.2)
            } else {
                hud = nil
            }
        }
    }

    private func hideHUD(after seconds: Double) {
        hudHide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.hud = nil
        }
    }

    private func startLevelMeter() {
        levelTimer?.invalidate()
        guard let recorder else { return }
        // 定时器挂在主线程的 RunLoop 上，回调本来就在主线程；直接声明出来，旧编译器（Swift 5.10）也认。
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let raw = Double(recorder.level)
                self.level += (raw - self.level) * 0.5
            }
        }
    }

    private func stopLevelMeter() {
        levelTimer?.invalidate()
        levelTimer = nil
        level = 0
    }

    func completeOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: Keys.onboarded)
    }

    // MARK: - 说过的话

    func reloadHistory() {
        history = (try? historyStore.recent(limit: 500)) ?? []
    }

    func deleteRecord(_ id: UUID) {
        try? historyStore.delete(id: id)
        reloadHistory()
    }

    func clearHistory() {
        try? historyStore.clear()
        reloadHistory()
    }

    var todayRecords: [TranscriptRecord] {
        history.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    var todayCharacters: Int {
        todayRecords.reduce(0) { $0 + $1.text.count }
    }

    /// 把本地历史导出到「下载」目录，返回文件 URL。
    func exportHistory() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else { return nil }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = downloads.appendingPathComponent("speakorb-history-\(stamp).json")
        guard (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    // MARK: - 服务钥匙

    func refreshKeys() {
        var set = Set<ProviderID>()
        for provider in ProviderID.allCases where keys.key(for: provider) != nil {
            set.insert(provider)
        }
        configuredProviders = set
    }

    @discardableResult
    func saveKey(_ key: String, for provider: ProviderID) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try keys.setKey(trimmed, for: provider)
            refreshKeys()
            return true
        } catch {
            lastError = .keychainFailed("\(error)")
            return false
        }
    }

    func removeKey(for provider: ProviderID) {
        try? keys.removeKey(for: provider)
        if settings.preferredProvider == provider {
            settings.preferredProvider = .local
        }
        refreshKeys()
    }

    // MARK: - 常用词

    func addTerm(_ raw: String, note: String = "") {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        guard !settings.dictionary.contains(where: { $0.term == term }) else { return }
        settings.dictionary.insert(DictionaryEntry(term: term, note: note.trimmingCharacters(in: .whitespacesAndNewlines)), at: 0)
    }

    func removeTerm(id: UUID) {
        settings.dictionary.removeAll { $0.id == id }
    }

    /// 从文本文件导入，一行一个词；“词,备注” 也可以。返回新加的个数。
    @discardableResult
    func importTerms(from url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let before = settings.dictionary.count
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ",", maxSplits: 1).map { String($0) }
            guard let term = parts.first else { continue }
            addTerm(term, note: parts.count > 1 ? parts[1] : "")
        }
        return settings.dictionary.count - before
    }

    // MARK: - 彻底删除

    struct DataSummary {
        let records: Int
        let terms: Int
        let keys: Int
    }

    var dataSummary: DataSummary {
        DataSummary(records: history.count, terms: settings.dictionary.count, keys: configuredProviders.count)
    }

    /// 删掉说过的话、常用词、钥匙和设置。App 本身由用户拖进废纸篓。
    func deleteEverything() {
        clearHistory()
        for provider in ProviderID.allCases {
            try? keys.removeKey(for: provider)
        }
        refreshKeys()
        settings = AppSettings()
        for key in [Keys.onboarded, Keys.theme, Keys.dock, Keys.language] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - 显示用

    var statusTitle: String {
        if paused && state == .idle { return tr("Paused", "已暂停") }
        switch state {
        case .listening: return tr("Listening…", "正在听你说…")
        case .transcribing, .injecting: return tr("Writing…", "正在写…")
        case .failed: return tr("Didn't work", "这次没成")
        case .idle: return missingSwitch == nil ? tr("Ready", "准备好了") : tr("One more step", "还差一步")
        }
    }

    var menuIcon: String {
        if paused && state == .idle { return "pause.circle" }
        switch state {
        case .listening: return "circle.fill"
        case .transcribing, .injecting: return "circle.dotted"
        case .failed: return "exclamationmark.circle"
        case .idle: return missingSwitch == nil ? "circle" : "exclamationmark.circle"
        }
    }

    var orbPhase: VoiceOrb.Phase {
        switch state {
        case .listening: return .listening
        case .transcribing, .injecting: return .writing
        case .failed: return .error
        case .idle: return .idle
        }
    }

    /// 给“复制错误信息”用：只有开关状态和错误代码，没有说过的话。固定用英文，方便维护者看。
    var diagnosticsReport: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        var lines = ["Speakorb \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for item in diagnostics { lines.append((item.ok ? "✓ " : "✗ ") + item.code) }
        lines.append("Default dictation: \(settings.preferredProvider.rawValue); connected services allowed: \(settings.allowCloud)")
        if let lastError { lines.append("Last failure: \(lastError.code)") }
        return lines.joined(separator: "\n")
    }

    func openAccessibility() { permissions.openAccessibilitySettings() }
    func openInputMonitoring() { permissions.openInputMonitoringSettings() }
    func requestMicrophone() { permissions.requestMicrophone() }

    @Published private(set) var speechGranted: Bool = SpeechTranscriber.authorizationStatus == .authorized

    func requestSpeech() {
        Task {
            let granted = await SpeechTranscriber.requestAuthorizationIfNeeded()
            self.speechGranted = granted
        }
    }

    func openSpeechSettings() {
        SpeechTranscriber.openSystemSettings()
    }

    func openDictationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
