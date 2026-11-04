import AppKit
import SwiftUI
import SpeakorbCore
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.onboardingComplete {
                MainWindowView()
            } else {
                OnboardingView()
            }
        }
        // 换语言时整棵界面重建，所有文字一起换。
        .id(model.language)
    }
}

/// 主窗口：左侧导航（说过的话 / 常用词 / 设置 / 帮助）+ 右侧内容。
struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Group {
                switch model.section {
                case .records: RecordsView()
                case .terms: TermsView()
                case .settings(let page): SettingsView(page: page)
                case .help: HelpView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.ttBackground)
        .foregroundStyle(Color.ttText)
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            item(tr("History", "说过的话"), "list.bullet", .records, count: model.history.count)
            item(tr("Custom words", "常用词"), "book.closed", .terms, count: model.settings.dictionary.count)
            item(tr("Settings", "设置"), "gearshape", .settings(.general), count: nil)
            Spacer()
            item(tr("Help & feedback", "帮助与反馈"), "questionmark.circle", .help, count: nil)
            HStack(spacing: 10) {
                VoiceOrb(size: 22, phase: model.orbPhase, level: model.level)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ProviderInfo.displayName(model.settings.preferredProvider)).font(.system(size: 12, weight: .semibold))
                    Text(model.settings.preferredProvider == .local ? model.localPrivacyShort : tr("Receives your audio", "录音会发给它"))
                        .font(.system(size: 11.5)).foregroundStyle(Color.ttMuted)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.ttField))
            .padding(.top, 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 46)
        .padding(.bottom, 14)
        .frame(width: 196)
        .background(Color.ttSidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.ttLine).frame(width: 1) }
    }

    private func isOn(_ target: AppModel.Section) -> Bool {
        switch (model.section, target) {
        case (.settings, .settings): return true
        default: return model.section == target
        }
    }

    private func item(_ title: String, _ icon: String, _ target: AppModel.Section, count: Int?) -> some View {
        let on = isOn(target)
        return Button {
            model.section = target
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.ttAccent).frame(width: 16)
                Text(title).font(.system(size: 13, weight: on ? .medium : .regular))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)").font(.ttMono(11)).foregroundStyle(Color.ttMuted)
                }
            }
            .foregroundStyle(on ? Color.ttText : Color.ttMuted)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.ttAccentSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? Color.ttAccentRing : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 页面顶部的标题栏（窗口标题栏是透明的，这里留出拖动区域）。
struct PageBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 15, weight: .bold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .overlay(alignment: .bottom) { RowDivider() }
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.ttMuted)
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12))
        }
        .padding(.horizontal, 9)
        .frame(width: 200, height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.ttField))
    }
}

// MARK: - 说过的话

struct RecordsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var selection: UUID?

    private var filtered: [TranscriptRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.history : model.history.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let missing = model.missingSwitch, !model.bannerDismissed {
                AttentionBanner(title: missing.title, detail: missing.detail, actionTitle: tr("Turn on", "去打开"), action: missing.open,
                                onClose: { model.bannerDismissed = true }, topInset: 28)
            }
            StatusHeader(topInset: model.missingSwitch == nil || model.bannerDismissed ? 28 : 0)
            if model.history.isEmpty {
                EmptyRecords()
            } else {
                HStack(spacing: 10) {
                    Text(tr("\(model.history.count) entries", "\(model.history.count) 段")).font(.system(size: 13)).foregroundStyle(Color.ttMuted)
                    Spacer()
                    SearchField(placeholder: tr("Search history", "搜索说过的话"), text: $query)
                    Button {
                        if let url = model.exportHistory() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    } label: { Label(tr("Export", "导出"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(.ttSecondary)
                }
                .padding(.horizontal, 20)
                .frame(height: 46)
                .overlay(alignment: .bottom) { RowDivider() }
                HStack(spacing: 0) {
                    recordList
                    if let record = model.history.first(where: { $0.id == selection }) {
                        RecordDetail(record: record, onDelete: {
                            model.deleteRecord(record.id)
                            selection = nil
                        })
                        .frame(width: 270)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: selection)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear { model.reloadHistory() }
    }

    private var recordList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                let items = filtered
                if items.isEmpty {
                    Text(tr("Nothing matches “\(query)”", "没有找到“\(query)”")).font(.system(size: 13)).foregroundStyle(Color.ttMuted).padding(20)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, record in
                    let day = TTDate.dayTitle(record.createdAt)
                    if index == 0 || TTDate.dayTitle(items[index - 1].createdAt) != day {
                        Text(day)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(Color.ttMuted)
                            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 4)
                    }
                    RecordRow(record: record, selected: record.id == selection)
                        .onTapGesture { selection = selection == record.id ? nil : record.id }
                        .contextMenu {
                            Button(tr("Copy", "复制")) { Clipboard.copy(record.text) }
                            Button(tr("Delete", "删除"), role: .destructive) { model.deleteRecord(record.id) }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}

private struct StatusHeader: View {
    @EnvironmentObject private var model: AppModel
    /// 透明标题栏下面留的高度；放在里面，背景的光才能一直铺到窗口顶。
    var topInset: CGFloat = 0

    var body: some View {
        HStack(spacing: 16) {
            VoiceOrb(size: 42, phase: model.orbPhase, level: model.level)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.statusTitle).font(.system(size: 16, weight: .semibold))
                if case .failed(let error) = model.state {
                    HStack(spacing: 8) {
                        Text(error.localizedMessage).font(.system(size: 12)).foregroundStyle(Color.ttWarn)
                        Button(tr("Try again", "重说")) { Task { await model.toggle() } }.buttonStyle(.ttPrimary).controlSize(.small)
                    }
                } else if model.paused {
                    HStack(spacing: 8) {
                        Text(tr("Right ⌥ won't record", "按右 ⌥ 不会录音")).font(.system(size: 12)).foregroundStyle(Color.ttMuted)
                        Button(tr("Resume", "继续听写")) { model.paused = false }.buttonStyle(.ttPrimary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(tr("Press", "按")).foregroundStyle(Color.ttMuted)
                        KeyCap(text: tr("Right ⌥", "右 ⌥"))
                        Text(tr("to start, again to finish ·", "开始，再按一下结束 ·")).foregroundStyle(Color.ttMuted)
                        KeyCap(text: "esc")
                        Text(tr("Cancel", "取消")).foregroundStyle(Color.ttMuted)
                    }
                    .font(.system(size: 12))
                }
            }
            Spacer()
            stat("\(model.todayCharacters.formatted())", tr("Characters today", "今天写了几个字"))
            stat("\(model.todayRecords.count)", tr("Entries today", "今天说了几段"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .padding(.top, topInset)
        .background(alignment: .topLeading) { Halo(size: 420).offset(x: -160, y: -230) }
        .clipped()
        .overlay(alignment: .bottom) { RowDivider() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value).font(.ttMono(19, weight: .semibold))
            Text(label).font(.system(size: 11)).foregroundStyle(Color.ttMuted)
        }
    }
}

private struct RecordRow: View {
    let record: TranscriptRecord
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(TTDate.time(record.createdAt))
                .font(.ttMono(11.5))
                .foregroundStyle(Color.ttMuted)
                .frame(width: 42, alignment: .leading)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.text).font(.system(size: 13)).lineLimit(2).lineSpacing(2)
                HStack(spacing: 8) {
                    DurationBars(durationMs: record.durationMs, seed: record.id.hashValue)
                    Text(TTDate.duration(ms: record.durationMs)).font(.ttMono(10.5)).foregroundStyle(Color.ttMuted)
                }
            }
            Spacer(minLength: 0)
            if hovering {
                Button { Clipboard.copy(record.text) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.ttSecondary)
                    .help(tr("Copy", "复制"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected || hovering ? Color.ttCard : .clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.ttAccentRing : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct RecordDetail: View {
    let record: TranscriptRecord
    let onDelete: () -> Void
    @State private var copied = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(TTDate.dayTitle(record.createdAt)) \(TTDate.time(record.createdAt))")
                Text(TTDate.duration(ms: record.durationMs))
                Text(ProviderInfo.displayName(record.provider))
            }
            .font(.ttMono(11))
            .foregroundStyle(Color.ttMuted)
            ScrollView {
                Text(record.text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(String(format: tr("Written in %.1f s · %d characters", "%.1f 秒写完 · %d 个字"), Double(record.latencyMs) / 1000, record.text.count))
                .font(.system(size: 11.5)).foregroundStyle(Color.ttMuted)
            HStack(spacing: 6) {
                Button {
                    Clipboard.copy(record.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: { Label(copied ? tr("COPIED", "已复制") : tr("Copy", "复制"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.ttPrimary)
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.ttSecondary)
                    .help(tr("Delete this entry", "删除这一段"))
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.ttCardAlt)
        .overlay(alignment: .leading) { Rectangle().fill(Color.ttLine).frame(width: 1) }
        .confirmationDialog(tr("Delete this entry?", "删除这一段？"), isPresented: $confirmDelete) {
            Button(tr("Delete", "删除"), role: .destructive, action: onDelete)
        } message: {
            Text(tr("This can't be undone.", "删了找不回来。"))
        }
    }
}

private struct EmptyRecords: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                OrbRings(size: 84)
                VoiceOrb(size: 84, phase: model.orbPhase, level: model.level)
            }
            .padding(.bottom, 44)
            Text(tr("Nothing here yet", "还没有说过话")).font(.system(size: 19, weight: .semibold))
            Text(tr("Click into any text field, tap the right ⌥ key and say something. What you say will show up here.", "把光标放进任意输入框，按一下右边的 ⌥，随便说一句。说完的话会出现在这里。"))
                .font(.system(size: 13))
                .foregroundStyle(Color.ttMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .lineSpacing(3)
            HStack(spacing: 10) {
                Button { model.section = .help } label: { Text(tr("How it works", "看看怎么用")) }
                    .buttonStyle(.ttSecondary)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { Halo(size: 420).offset(y: -60) }
        .clipped()
    }
}

// MARK: - 常用词

struct TermsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var term = ""
    @State private var note = ""
    @FocusState private var termFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PageBar(title: tr("Custom words", "常用词")) {
                Button { importFile() } label: { Label(tr("Import from file", "从文件导入"), systemImage: "square.and.arrow.down") }
                    .buttonStyle(.ttSecondary)
            }
            .padding(.top, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tr("Names, products, places, jargon. Add them and dictation will get them right. Stored only on this Mac.", "人名、产品名、地名、行话。加进来以后，听写会优先写对它们。只存在这台 Mac 上。"))
                        .font(.system(size: 12.5)).foregroundStyle(Color.ttMuted)
                    HStack(spacing: 8) {
                        field(tr("Add a word", "加一个词"), text: $term).focused($termFocused)
                        field(tr("Note (optional)", "备注（可不填）"), text: $note).frame(maxWidth: 220)
                        Button(tr("Add", "加上"), action: add)
                            .buttonStyle(.ttPrimary)
                            .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
                            .keyboardShortcut(.defaultAction)
                    }
                    if model.settings.dictionary.isEmpty {
                        Text(tr("No custom words yet. Try adding a colleague's name so it's never misspelled.", "还没有常用词。比如加上同事的名字，听写就不会写成同音字。"))
                            .font(.system(size: 13)).foregroundStyle(Color.ttMuted).padding(.top, 20)
                    } else {
                        SectionLabel(text: tr("\(model.settings.dictionary.count) WORDS · NEWEST FIRST", "\(model.settings.dictionary.count) 个词 · 最新加的在前面"))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(model.settings.dictionary) { entry in
                                TermChip(entry: entry) { model.removeTerm(id: entry.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.ttField))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.ttLine))
            .onSubmit(add)
    }

    private func add() {
        model.addTerm(term, note: note)
        term = ""
        note = ""
        termFocused = true
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText]
        panel.message = tr("Choose a text file: one word per line, or “word,note”", "选一个文本文件：一行一个词，也可以写成“词,备注”")
        if panel.runModal() == .OK, let url = panel.url {
            model.importTerms(from: url)
        }
    }
}

private struct TermChip: View {
    let entry: DictionaryEntry
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.term).font(.system(size: 13.5)).lineLimit(1)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.system(size: 11)).foregroundStyle(Color.ttMuted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.ttField))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ttMuted)
                .accessibilityLabel(tr("Remove \(entry.term)", "删掉 \(entry.term)"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.ttCard))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(hovering ? Color.ttAccentRing : Color.ttLine))
        .onHover { hovering = $0 }
    }
}

// MARK: - 帮助与反馈

struct HelpView: View {
    @EnvironmentObject private var model: AppModel
    @State private var open: Int? = 0
    @State private var showCheck = false
    @State private var copied = false

    private let faq: [(String, [String])] = [
        (tr("Nothing happens when I press right ⌥?", "按了右 ⌥ 没反应？"), [
            tr("Look at the small circle in the menu bar: an exclamation mark means a permission is missing. Click it to fix.", "看菜单栏的小圆圈：有感叹号说明还差一个开关，点它就能补上。"),
            tr("Use the ⌥ key on the right; the left one doesn't count.", "按的是右边那个 ⌥，左边的不算。"),
            tr("If you just turned on a permission, quit Speakorb and open it again.", "刚打开开关的话，退出声球再打开一次。"),
        ]),
        (tr("The text didn't appear in the field?", "字没有出现在输入框里？"), [
            tr("Speakorb needs the Accessibility permission to put text into fields.", "需要打开“辅助功能”开关，声球才能把字放进去。"),
            tr("Some fields don't accept it (password fields, some terminals). The text is already copied — press ⌘V.", "有些地方不让直接放字（比如密码框、部分终端），这时字已经复制好了，按 ⌘V 粘贴。"),
        ]),
        (tr("Does it work offline?", "不联网能用吗？"), [
            tr("Yes, with an offline language pack: System Settings → Keyboard → Dictation, then download the language.", "装了离线语言包就可以：系统设置 → 键盘 → 听写，下载你说的语言。"),
            tr("Without it, on-device dictation needs the internet, but never an account.", "没装时，本机听写需要联网，但不需要任何账号。"),
        ]),
        (tr("Is my audio uploaded?", "我的录音会被上传吗？"), [
            tr("With an offline language pack, on-device dictation never leaves this Mac. Without it, macOS sends audio to Apple.", "装了离线语言包时，本机听写的录音不会离开这台 Mac；没装时，系统会把录音交给 Apple 处理。"),
            tr("Audio only goes to Gemini or another service if you connect it and choose it as the default.", "只有你接入了 Gemini 等服务并选它做默认时，录音才会发给那一家。"),
        ]),
        (tr("What if I mix Chinese and English?", "中英混着说会写错吗？"), [
            tr("That usually works. Add names and products that come out wrong to Custom words.", "一般不会。常写错的人名、产品名，加到“常用词”里就会优先写对。"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageBar(title: tr("Help & feedback", "帮助与反馈")) { EmptyView() }
                .padding(.top, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(faq.enumerated()), id: \.offset) { index, item in
                        question(index, item.0, item.1)
                    }
                    if showCheck {
                        SettingsGroup {
                            ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { index, check in
                                if index > 0 { RowDivider() }
                                SettingsRow(title: check.title, detail: check.ok ? nil : check.hint) {
                                    Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundStyle(check.ok ? Color.ttOK : Color.ttWarn)
                                }
                            }
                        }
                        .padding(.top, 6)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle").foregroundStyle(Color.ttMuted)
                        Text(tr("Still stuck? Send us the diagnostics. They never include anything you said.", "还是不行？把错误信息发给我们，里面不含你说过的话。")).font(.system(size: 13))
                        Spacer()
                        Button {
                            Clipboard.copy(model.diagnosticsReport)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        } label: { Label(copied ? tr("COPIED", "已复制") : tr("Copy diagnostics", "复制错误信息"), systemImage: copied ? "checkmark" : "doc.on.doc") }
                            .buttonStyle(.ttSecondary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.ttField))
                    .padding(.top, 8)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private func question(_ index: Int, _ title: String, _ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { open = open == index ? nil : index }
            } label: {
                HStack {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    Image(systemName: open == index ? "minus" : "plus").foregroundStyle(Color.ttMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open == index {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { n, step in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(n + 1).").font(.ttMono(12)).foregroundStyle(Color.ttMuted)
                            Text(step).font(.system(size: 12.5)).foregroundStyle(Color.ttMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if index == 0 {
                    Button {
                        model.refreshStatus()
                        withAnimation { showCheck = true }
                    } label: { Label(tr("Check everything", "帮我检查一遍"), systemImage: "checkmark") }
                        .buttonStyle(.ttPrimary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ttCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ttLine))
    }
}
