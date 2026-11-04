import AppKit
import SwiftUI
import SpeakorbCore

/// 设置：左侧五页，每页只讲一件事。
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    let page: AppModel.SettingsPage

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppModel.SettingsPage.allCases) { item in
                    Button { model.section = .settings(item) } label: {
                        HStack {
                            Text(item.title).font(.system(size: 13, weight: item == page ? .medium : .regular))
                            Spacer()
                            if item == .local && !model.offlineAvailable {
                                Circle().fill(Color.ttWarn).frame(width: 6, height: 6)
                            }
                        }
                        .foregroundStyle(item == page ? Color.ttText : Color.ttMuted)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(item == page ? Color.ttField : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 46)
            .frame(width: 170)
            .overlay(alignment: .trailing) { Rectangle().fill(Color.ttLine).frame(width: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch page {
                    case .general: GeneralSettings()
                    case .cloud: CloudSettings()
                    case .local: LocalSettings()
                    case .privacy: PrivacySettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 46)
                .padding(.bottom, 22)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

private struct LabeledGroup<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            SettingsGroup { content }
        }
    }
}

// MARK: 通用

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        LabeledGroup(label: tr("LANGUAGE", "语言")) {
            SettingsRow(title: tr("Interface language", "界面语言"), detail: tr("The language of menus and buttons", "菜单和按钮用的语言")) {
                Picker("", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            RowDivider()
            SettingsRow(title: tr("You speak", "你说"), detail: model.dictationLanguage.detail) {
                DictationLanguagePicker()
            }
        }
        LabeledGroup(label: tr("APPEARANCE", "外观")) {
            SettingsRow(title: tr("Theme", "主题"), detail: tr("Daylight is the default; Night is the glowing dark one", "日光是默认；夜光是带光晕的深色")) {
                Picker("", selection: $model.theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        LabeledGroup(label: tr("TALK KEY", "说话键")) {
            HStack(spacing: 12) {
                KeyCap(text: tr("Right ⌥", "右 ⌥"), large: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Tap once to start, again to finish", "轻点一下开始，再点一下结束")).font(.system(size: 13))
                    Text(tr("Press esc anytime to cancel", "按 esc 随时取消这一次")).font(.system(size: 11.5)).foregroundStyle(Color.ttMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        LabeledGroup(label: tr("STARTUP", "启动")) {
            SettingsRow(title: tr("Open at login", "开机时自动打开")) { TTToggle(isOn: $model.settings.launchAtLogin) }
            RowDivider()
            SettingsRow(title: tr("Show in Dock", "在程序坞显示图标"), detail: tr("When off, Speakorb lives in the menu bar", "关掉后只在菜单栏")) { TTToggle(isOn: $model.showInDock) }
            RowDivider()
            SettingsRow(title: tr("Pause dictation", "暂停听写"), detail: tr("While paused, right ⌥ won't record until you resume", "暂停后按右 ⌥ 不会录音，直到你继续")) { TTToggle(isOn: $model.paused) }
        }
    }
}

// MARK: 更准的听写

private struct CloudSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: ProviderID?

    var body: some View {
        Text(tr("Optional. Connect your own service for better accuracy, especially with names and mixed languages.", "不接也能用。接入你自己的服务后，字会更准，尤其是人名和中英混说。"))
            .font(.system(size: 12.5)).foregroundStyle(Color.ttMuted)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(ProviderInfo.all, id: \.id) { info in
                providerCard(info)
            }
        }
        LabeledGroup(label: tr("WHICH ONE", "用哪个")) {
            SettingsRow(title: tr("Use by default", "默认用"), detail: model.settings.preferredProvider == .local
                        ? tr("On-device dictation: \(model.localPrivacyShort)", "本机听写：\(model.localPrivacyShort)")
                        : preferredPrivacyLine) {
                Picker("", selection: $model.settings.preferredProvider) {
                    Text(tr("On-device dictation", "本机听写")).tag(ProviderID.local)
                    ForEach(ProviderInfo.all.filter { model.configuredProviders.contains($0.id) }, id: \.id) { info in
                        Text(info.name).tag(info.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            RowDivider()
            SettingsRow(title: tr("Allow connected services", "允许用我接入的服务"), detail: tr("When off, always use on-device dictation", "关掉后一律用本机听写")) {
                TTToggle(isOn: $model.settings.allowCloud)
            }
        }
        .sheet(item: Binding(get: { editing.map(EditingProvider.init) }, set: { editing = $0?.id })) { item in
            ConnectSheet(provider: item.id).environmentObject(model)
        }
    }

    private var preferredPrivacyLine: String {
        let name = ProviderInfo.displayName(model.settings.preferredProvider)
        let privacy = ProviderInfo.of(model.settings.preferredProvider)?.privacy ?? ""
        return tr("\(name): \(privacy.lowercased())", "选 \(name) 时，\(privacy)")
    }

    private func providerCard(_ info: ProviderInfo) -> some View {
        let on = model.configuredProviders.contains(info.id)
        return Button { editing = info.id } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    ProviderLogo(info: info)
                    Text(info.name).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    if on { Pill(text: tr("Connected", "已接入"), tone: .ok) }
                }
                HStack {
                    Text(info.privacy)
                    Spacer()
                    Text(on ? tr("Manage", "管理") : tr("Connect →", "接入 →"))
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.ttMuted)
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.ttCard))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.ttAccentRing : Color.ttLine))
            .shadow(color: on ? Color.ttHalo : .clear, radius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EditingProvider: Identifiable {
    let id: ProviderID
}

/// 接入向导：选服务 ✓ → 粘贴钥匙 → 接好了。
struct ConnectSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let provider: ProviderID

    @State private var key = ""
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var saved = false
    @State private var makeDefault = true
    @State private var confirmRemove = false

    private var info: ProviderInfo { ProviderInfo.of(provider) ?? ProviderInfo.all[0] }
    private var configured: Bool { model.configuredProviders.contains(provider) }
    private var canSave: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (provider != .custom || (!baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !modelName.trimmingCharacters(in: .whitespaces).isEmpty))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            steps
            HStack(spacing: 12) {
                ProviderLogo(info: info, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(saved ? tr("\(info.name) is connected", "\(info.name) 接好了") : tr("Connect \(info.name)", "接入 \(info.name)")).font(.system(size: 18, weight: .bold))
                    Text(saved ? tr("Dictation will be more accurate from now on.", "以后听写会更准。") : tr("The key \(info.name) gave you", "\(info.name) 给你的那串钥匙")).font(.system(size: 12)).foregroundStyle(Color.ttMuted)
                }
            }
            if saved {
                SettingsGroup {
                    SettingsRow(title: tr("Use for dictation", "设为默认听写"), detail: tr("Right ⌥ will use \(info.name) from now on", "以后按右 ⌥ 说话都用 \(info.name)")) { TTToggle(isOn: $makeDefault) }
                }
                Text(tr("Your key is stored in this Mac's Keychain and never uploaded.", "钥匙存在这台 Mac 的钥匙串里，不会上传。")).font(.system(size: 11.5)).foregroundStyle(Color.ttMuted)
                HStack {
                    Spacer()
                    Button(tr("Done", "完成")) {
                        if makeDefault { model.settings.preferredProvider = provider; model.settings.allowCloud = true }
                        dismiss()
                    }
                    .buttonStyle(.ttPrimary)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: provider == .deepseek ? "text.bubble" : "icloud").foregroundStyle(Color.ttWarn)
                    Text(provider == .deepseek
                         ? tr("DeepSeek receives text only, never audio: your Mac transcribes first, then DeepSeek tidies it up.", "DeepSeek 只收文字，不收录音：先在本机听写，再让它整理。")
                         : tr("When you use \(info.name), your audio is sent to it. If you'd rather not upload, skip this and keep using on-device dictation.", "用 \(info.name) 时，你的录音会发给它。不想上传，就别接，继续用本机听写。"))
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.ttWarnSoft))
                if provider == .custom {
                    input(tr("Server address, e.g. http://127.0.0.1:11434/v1", "服务地址，例如 http://127.0.0.1:11434/v1"), text: $baseURL)
                    input(tr("Name, e.g. qwen3:8b", "名字，例如 qwen3:8b"), text: $modelName)
                }
                SecureField(configured ? tr("Paste a new key to replace it", "粘贴新的钥匙来更换") : tr("Paste your key", "粘贴钥匙"), text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.ttField))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.ttAccentRing, lineWidth: 1.5))
                if let error = model.lastError, case .keychainFailed = error {
                    Text(error.localizedMessage).font(.system(size: 12)).foregroundStyle(Color.ttBad)
                }
                HStack(spacing: 8) {
                    if let url = info.helpURL {
                        Button(tr("Where do I get a key? ↗", "去哪里拿钥匙？ ↗")) { NSWorkspace.shared.open(url) }
                            .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Color.ttAccent)
                    }
                    if configured {
                        Button(tr("Remove", "移除")) { confirmRemove = true }
                            .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Color.ttBad)
                    }
                    Spacer()
                    Button(tr("Cancel", "取消")) { dismiss() }.buttonStyle(.ttSecondary).keyboardShortcut(.cancelAction)
                    Button(tr("Save", "保存"), action: save).buttonStyle(.ttPrimary).disabled(!canSave).keyboardShortcut(.defaultAction)
                }
                Text(tr("Your key is stored in this Mac's Keychain and never uploaded.", "钥匙存在这台 Mac 的钥匙串里，不会上传。")).font(.system(size: 11.5)).foregroundStyle(Color.ttMuted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 520)
        .background(Color.ttBackground)
        .foregroundStyle(Color.ttText)
        .onAppear {
            baseURL = model.settings.customBaseURL
            modelName = model.settings.customModel
            makeDefault = model.settings.preferredProvider == .local
        }
        .confirmationDialog(tr("Remove the \(info.name) key?", "移除 \(info.name) 的钥匙？"), isPresented: $confirmRemove) {
            Button(tr("Remove", "移除"), role: .destructive) {
                model.removeKey(for: provider)
                dismiss()
            }
        } message: {
            Text(tr("Speakorb will switch to on-device dictation.", "移除后会改用本机听写。"))
        }
    }

    private var steps: some View {
        HStack(spacing: 8) {
            step(1, tr("Choose", "选服务"), done: true, current: false)
            Rectangle().fill(Color.ttLine).frame(height: 1)
            step(2, tr("Paste your key", "粘贴钥匙"), done: saved, current: !saved)
            Rectangle().fill(Color.ttLine).frame(height: 1)
            step(3, tr("Connected", "接好了"), done: false, current: saved)
        }
        .font(.system(size: 12))
    }

    private func step(_ n: Int, _ title: String, done: Bool, current: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(done ? Color.ttOK : current ? Color.ttBrand : Color.clear)
                Circle().strokeBorder(done || current ? Color.clear : Color.ttLine)
                Text(done ? "✓" : "\(n)").font(.ttMono(10, weight: .semibold)).foregroundStyle(done || current ? Color.white : Color.ttMuted)
            }
            .frame(width: 18, height: 18)
            Text(title).foregroundStyle(current ? Color.ttText : Color.ttMuted).fontWeight(current ? .semibold : .regular)
        }
        .fixedSize()
    }

    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.ttField))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.ttLine))
    }

    private func save() {
        if provider == .custom {
            model.settings.customBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            model.settings.customModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if model.saveKey(key, for: provider) {
            withAnimation(.easeOut(duration: 0.2)) { saved = true }
        }
    }
}

// MARK: 本机听写

private struct LocalSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            VoiceOrb(size: 46, phase: model.localASRAvailable ? .idle : .error)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.localASRAvailable ? (model.offlineAvailable ? tr("On-device dictation · works offline", "本机听写 · 断网也能用") : tr("On-device dictation · ready", "本机听写 · 可以用")) : tr("On-device dictation · unavailable", "本机听写 · 暂时不能用"))
                    .font(.system(size: 15, weight: .semibold))
                Text(model.offlineAvailable
                     ? tr("The offline language pack is installed, so what you say never leaves this Mac.", "离线语言包已经装好，说的话完全不离开这台 Mac。")
                     : model.localASRAvailable
                        ? tr("Needs the internet for now. Install the offline language pack to dictate offline.", "现在需要联网。装上离线语言包后，断网也能听写。")
                        : tr("Turn on Speech Recognition, or connect a service under Better accuracy.", "需要打开“语音识别”开关；或者在“更准的听写”里接入一个服务。"))
                    .font(.system(size: 12)).foregroundStyle(Color.ttMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !model.speechGranted {
                Button(tr("Turn on", "打开开关")) { model.requestSpeech() }.buttonStyle(.ttPrimary)
            } else if !model.offlineAvailable {
                Button(tr("Get offline pack", "去装离线包")) { model.openDictationSettings() }.buttonStyle(.ttPrimary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ttCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ttLine))
        if !model.offlineAvailable && model.speechGranted {
            Text(tr("In System Settings → Keyboard → Dictation, add \(model.dictationLanguage.displayName) and macOS will download the pack.", "在“系统设置 → 键盘 → 听写”里加上\(model.dictationLanguage.displayName)，系统会下载离线包。"))
                .font(.system(size: 12)).foregroundStyle(Color.ttMuted)
        }
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                SectionLabel(text: tr("BETTER ON-DEVICE DICTATION", "更好的本机听写"))
                Pill(text: tr("Coming soon", "即将推出"), tone: .soon)
            }
            SettingsGroup {
                SettingsRow(title: tr("Download once, accurate even offline", "下载一次，断网也更准"), detail: tr("About 850 MB. Speakorb switches over quietly once it's ready.", "约 850 MB。准备好以后会自动换过去，不打扰你。")) { EmptyView() }
            }
        }
    }
}

// MARK: 隐私

private struct PrivacySettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmClear = false

    var body: some View {
        let usingLocal = model.settings.preferredProvider == .local || !model.settings.allowCloud
        SettingsGroup {
            statement("laptopcomputer", model.localPrivacyLine, current: usingLocal)
            RowDivider()
            statement("icloud", cloudLine, current: !usingLocal)
            RowDivider()
            statement("lock", tr("Your key is stored in this Mac's Keychain and never uploaded.", "钥匙存在这台 Mac 的钥匙串里，不会上传。"), current: false)
            RowDivider()
            statement("shield", tr("Speakorb has no servers and no accounts, and collects no usage data.", "声球没有服务器，也没有账号，不收集任何使用数据。"), current: false)
        }
        LabeledGroup(label: tr("DATA", "数据")) {
            SettingsRow(title: tr("History", "说过的话"), detail: tr("\(model.history.count) entries, stored only on this Mac", "\(model.history.count) 段，只存在这台 Mac 上")) {
                HStack(spacing: 6) {
                    Button { if let url = model.exportHistory() { NSWorkspace.shared.activateFileViewerSelecting([url]) } } label: {
                        Label(tr("Export", "导出"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.ttSecondary)
                    Button(tr("Delete all", "全部删掉")) { confirmClear = true }
                        .buttonStyle(.ttSecondary)
                        .foregroundStyle(Color.ttBad)
                        .disabled(model.history.isEmpty)
                }
            }
        }
        .confirmationDialog(tr("Delete all \(model.history.count) entries?", "删掉全部 \(model.history.count) 段说过的话？"), isPresented: $confirmClear) {
            Button(tr("Delete all", "全部删掉"), role: .destructive) { model.clearHistory() }
        } message: {
            Text(tr("This can't be undone. Custom words and settings are kept.", "删了找不回来。常用词和设置不受影响。"))
        }
    }

    private var cloudLine: String {
        if let info = ProviderInfo.of(model.settings.preferredProvider), model.settings.allowCloud {
            return info.id == .deepseek ? tr("When you use DeepSeek, only text is sent, never audio.", "用 DeepSeek 时，只把文字发给它，不发录音。") : tr("When you use \(info.name), your audio is sent to \(info.name). Don't connect it if you'd rather not upload.", "用 \(info.name) 时，录音会发给 \(info.name)。不想上传就别接。")
        }
        return tr("Connected services receive your audio. Nothing is uploaded unless you connect one.", "接入服务后，录音会发给那一家。不接就不会上传。")
    }

    private func statement(_ icon: String, _ text: String, current: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.ttAccent).frame(width: 18)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if current { Pill(text: tr("Now", "现在"), tone: .ok) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: 关于

private struct AboutSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Speakorb", "声球")).font(.system(size: 18, weight: .bold))
                Text(tr("Speakorb \(version) (preview) · free and open source", "Speakorb \(version)（内测版） · 免费开源")).font(.system(size: 12)).foregroundStyle(Color.ttMuted)
            }
        }
        SettingsGroup {
            SettingsRow(title: tr("Automatic updates", "自动更新"), detail: tr("Not available yet; new versions are posted on the project page", "还没上线，新版本先在项目主页发布")) { Pill(text: tr("Coming soon", "即将推出"), tone: .soon) }
        }
        Button(tr("Delete all Speakorb data…", "彻底删除声球的所有数据…")) { confirmDelete = true }
            .buttonStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(Color.ttBad)
            .padding(.top, 24)
            .sheet(isPresented: $confirmDelete) {
                DeleteEverythingSheet().environmentObject(model)
            }
    }
}

struct DeleteEverythingSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var done = false

    var body: some View {
        let summary = model.dataSummary
        VStack(alignment: .leading, spacing: 14) {
            Text(done ? tr("Everything is deleted", "都删掉了") : tr("Delete all Speakorb data?", "彻底删除声球的数据？")).font(.system(size: 18, weight: .bold))
            if done {
                Text(tr("History, custom words, keys and settings are gone. Drag the app itself to the Trash.", "说过的话、常用词、钥匙和设置都已经删掉。App 本身请拖到废纸篓。"))
                    .font(.system(size: 13)).foregroundStyle(Color.ttMuted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(tr("Quit Speakorb", "退出声球")) { NSApp.terminate(nil) }.buttonStyle(.ttPrimary).keyboardShortcut(.defaultAction)
                }
            } else {
                Text(tr("These will be removed from this Mac. This can't be undone.", "下面这些会从这台 Mac 上删掉，删了找不回来。")).font(.system(size: 13)).foregroundStyle(Color.ttMuted)
                VStack(alignment: .leading, spacing: 6) {
                    row(tr("History", "说过的话"), tr("\(summary.records) entries", "\(summary.records) 段"))
                    row(tr("Custom words", "常用词"), tr("\(summary.terms)", "\(summary.terms) 个"))
                    row(tr("Service keys", "接入的钥匙"), tr("\(summary.keys)", "\(summary.keys) 把"))
                    row(tr("Settings", "设置"), "")
                }
                Text(tr("Then drag the app itself to the Trash.", "App 本身请再拖到废纸篓。")).font(.system(size: 12)).foregroundStyle(Color.ttMuted)
                HStack {
                    Spacer()
                    Button(tr("Cancel", "取消")) { dismiss() }.buttonStyle(.ttSecondary).keyboardShortcut(.cancelAction)
                    Button(tr("Delete everything", "全部删除")) {
                        model.deleteEverything()
                        done = true
                    }
                    .buttonStyle(.ttDanger)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color.ttBackground)
        .foregroundStyle(Color.ttText)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 4).fill(Color.ttBad))
            Text(title).font(.system(size: 13))
            Spacer()
            Text(value).font(.ttMono(12)).foregroundStyle(Color.ttMuted)
        }
    }
}
