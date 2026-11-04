import Combine
import SwiftUI
import SpeakorbCore

/// 首次引导三屏：欢迎 → 打开开关 → 说一句试试。固定用日光配色、大字、52pt 大按钮。
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State var step = 0

    var body: some View {
        ZStack {
            Day.background
            switch step {
            case 0: WelcomeStep(next: { go(1) })
            case 1: PermissionsStep(back: { go(0) }, next: { go(2) })
            default: TryStep(back: { go(1) }, finish: { model.completeOnboarding() })
            }
        }
        .frame(width: 720, height: 560)
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
        .foregroundStyle(Day.text)
    }

    private func go(_ next: Int) {
        withAnimation(.easeOut(duration: 0.25)) { step = next }
    }
}

private struct DayButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .padding(.horizontal, 26)
            .frame(minHeight: 52)
            .foregroundStyle(primary ? Color.white : Day.text)
            .background(Capsule().fill(primary ? Day.brand : Color.white))
            .overlay(Capsule().strokeBorder(primary ? Color.clear : Day.line, lineWidth: 1.5))
            .shadow(color: primary ? Day.brand.opacity(0.3) : .clear, radius: 10, y: 6)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

private struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(Day.muted)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// 左边的大键帽。
private struct BigKey: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Text("⌥").font(.system(size: 54, weight: .semibold)).frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(tr("the right one", "右边这个键")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Day.muted).padding(.bottom, 10)
        }
        .frame(width: 170, height: 122)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [.white, Color(nsColor: NSColor(hex: 0xF1EFF8))], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(nsColor: NSColor(hex: 0xCFC9E4)), radius: 0, y: 10)
                .shadow(color: Color(nsColor: NSColor(hex: 0x3C3278, alpha: 0.2)), radius: 20, y: 24)
        )
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color(nsColor: NSColor(hex: 0xD6D1EC)), lineWidth: 1.5))
        .accessibilityLabel(tr("The right Option key", "右边的 Option 键"))
    }
}

/// 第一屏右上角的语言切换：English / 中文。
private struct LanguagePicker: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppLanguage.allCases) { lang in
                let on = model.language == lang
                Button(lang.nativeName) { model.language = lang }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Day.text : Day.muted)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(on ? Color.white : .clear))
                    .shadow(color: on ? Color.black.opacity(0.08) : .clear, radius: 2, y: 1)
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Day.quiet))
        .accessibilityLabel("Language / 语言")
    }
}

private struct WelcomeStep: View {
    @EnvironmentObject private var model: AppModel
    let next: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floatUp = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(nsColor: NSColor(hex: 0xEAE5FF)), Color(nsColor: NSColor(hex: 0xFFEBDD))], startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 36) {
                    VoiceOrb(size: 66)
                        .offset(y: floatUp ? -8 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: floatUp)
                    BigKey()
                }
            }
            .frame(width: 360)
            .onAppear { floatUp = true }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(tr("SPEAKORB", "声球 · SPEAKORB"))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Day.brand)
                    Spacer()
                    LanguagePicker()
                }
                Text(tr("Speak.\nIt types.", "说完，\n就有字")).font(.system(size: 32, weight: .heavy)).lineSpacing(4)
                Text(tr("Tap the right ⌥ key and start talking. Tap it again when you're done, and the words appear wherever you're typing.", "按一下右边的 ⌥ 开始说话，说完再按一下。字会出现在你正在打字的地方。"))
                    .font(.system(size: 17)).foregroundStyle(Day.muted).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    point(1, tr("No sign-up, nothing to fill in", "不用注册，不用填任何东西"))
                    point(2, tr("Works in chat, Notes, Mail and more", "微信、备忘录、邮件都能用"))
                    point(3, tr("No accounts, and no servers of ours", "没有账号，也没有我们的服务器"))
                }
                .padding(.top, 6)
                Spacer()
                HStack {
                    Text(tr("About 2 minutes", "约 2 分钟设置好")).font(.system(size: 14)).foregroundStyle(Day.muted)
                    Spacer()
                    Button(tr("Get started", "开始")) {
                        // 第一次用：你说的话默认和界面同一种语言，第 3 步和设置里都能改。
                        model.dictationLanguage = model.language.defaultDictation
                        next()
                    }
                    .buttonStyle(DayButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 70)
            .padding(.bottom, 26)
        }
    }

    private func point(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .heavy)).foregroundStyle(Day.brand)
                .frame(width: 22, height: 22).background(Circle().fill(Day.brandSoft))
            Text(text).font(.system(size: 15))
        }
    }
}

/// 左侧紫色说明栏，第 2、3 步共用。
private struct StepArt: View {
    let step: Int
    let title: String
    let text: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x5B4BE0)), Color(nsColor: NSColor(hex: 0x7A5CF0))], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(RadialGradient(colors: [.white, Color(nsColor: NSColor(hex: 0xFFD9B8)), Color(nsColor: NSColor(hex: 0xFF9F5A)), Color(nsColor: NSColor(hex: 0xFF9F5A, alpha: 0))],
                                     center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: 160))
                .frame(width: 220, height: 220)
                .offset(x: 70, y: 70)
                .opacity(0.9)
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Step \(step) of 3", "第 \(step) 步，共 3 步")).font(.system(size: 13, weight: .semibold)).opacity(0.85)
                Text(title).font(.system(size: 28, weight: .heavy))
                Text(text).font(.system(size: 15)).opacity(0.88).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { i in
                        Capsule().fill(Color.white.opacity(i <= step ? 1 : 0.3)).frame(height: 6)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 52)
            .padding(.bottom, 22)
        }
        .foregroundStyle(.white)
        .frame(width: 260)
        .clipped()
    }
}

private struct PermissionsStep: View {
    @EnvironmentObject private var model: AppModel
    let back: () -> Void
    let next: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct Item {
        let icon: String
        let title: String
        let detail: String
        let granted: Bool
        let open: () -> Void
    }

    private var items: [Item] {
        [
            Item(icon: "mic", title: tr("Microphone", "麦克风"), detail: tr("To hear you", "听见你说话"), granted: model.permissions.microphoneGranted, open: model.requestMicrophone),
            Item(icon: "keyboard", title: tr("Input Monitoring", "输入监控"), detail: tr("So right ⌥ becomes your talk key", "让右 ⌥ 变成说话键"), granted: model.permissions.inputMonitoringGranted, open: model.openInputMonitoring),
            Item(icon: "character.cursor.ibeam", title: tr("Accessibility", "辅助功能"), detail: tr("To put text into fields", "把字放进输入框"), granted: model.permissions.accessibilityGranted, open: model.openAccessibility),
            Item(icon: "waveform", title: tr("Speech Recognition", "语音识别"), detail: tr("Dictation without any service", "不接服务也能听写"), granted: model.speechGranted, open: model.requestSpeech),
        ]
    }

    var body: some View {
        let list = items
        let current = list.firstIndex { !$0.granted }
        HStack(spacing: 0) {
            StepArt(step: 2, title: tr("Turn on \(list.count) permissions", "打开 \(list.count) 个开关"), text: tr("So Speakorb can hear you and put your words in place. You only do this once.", "这样声球才能听见你说话，再把字放进去。只需要开一次。"))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, item in
                    card(item, isCurrent: index == current)
                }
                HStack(spacing: 8) {
                    if current != nil {
                        ProgressView().controlSize(.small)
                        Text(tr("Each one ticks itself once it's on", "打开以后会自动打勾，不用回来点")).font(.system(size: 13)).foregroundStyle(Day.muted)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Day.ok)
                        Text(tr("All set", "都打开了")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Day.okText)
                    }
                }
                .padding(.top, 4)
                Spacer()
                HStack {
                    Button(tr("Back", "上一步"), action: back).buttonStyle(LinkButtonStyle())
                    Spacer()
                    if current != nil {
                        Button(tr("Later", "以后再说"), action: next).buttonStyle(LinkButtonStyle()).padding(.trailing, 14)
                    }
                    Button(tr("Next", "下一步"), action: next)
                        .buttonStyle(DayButtonStyle(primary: current == nil))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 28)
            .padding(.bottom, 22)
        }
        .onReceive(timer) { _ in model.refreshStatus() }
    }

    private func card(_ item: Item, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Day.brand)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12).fill(Day.brandSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 16, weight: .semibold))
                Text(item.detail).font(.system(size: 13)).foregroundStyle(Day.muted)
            }
            Spacer()
            if item.granted {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Day.ok))
                    .accessibilityLabel(tr("On", "已打开"))
            } else {
                Button(tr("Turn on", "去打开"), action: item.open)
                    .font(.system(size: 15, weight: .bold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .foregroundStyle(isCurrent ? Color.white : Day.muted)
                    .background(Capsule().fill(isCurrent ? Day.brand : Day.quiet))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Day.card))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(isCurrent ? Day.brand : .clear, lineWidth: 2))
        .animation(.easeOut(duration: 0.2), value: item.granted)
    }
}

private struct TryStep: View {
    @EnvironmentObject private var model: AppModel
    let back: () -> Void
    let finish: () -> Void
    @State private var practice = ""
    @State private var succeeded = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            StepArt(step: 3, title: tr("Try it", "说一句试试"), text: tr("Tap the right ⌥ key, say something, then tap it again.", "按一下右边的 ⌥，说一句话，再按一下。"))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(tr("You'll speak", "你会说")).font(.system(size: 14)).foregroundStyle(Day.muted)
                    DictationLanguagePicker()
                    Spacer()
                }
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $practice)
                        .font(.system(size: 18))
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .padding(14)
                    if practice.isEmpty {
                        Text(tr("Your cursor is already here. Tap right ⌥ and speak…", "光标已经在这里了。按右 ⌥ 说一句…"))
                            .font(.system(size: 18))
                            .foregroundStyle(Color(nsColor: NSColor(hex: 0xA6A2BD)))
                            .padding(.horizontal, 19).padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 150)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Day.brand, lineWidth: 2))
                .shadow(color: Day.brand.opacity(0.14), radius: 15, y: 8)

                if succeeded {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(Circle().fill(Day.ok))
                        Text(tr("It works! Do the same anywhere you type.", "成功了！以后在任何地方都这样说话。")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Day.okText)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Day.okSoft))
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else if let error = model.lastError {
                    Text(error.localizedMessage).font(.system(size: 14)).foregroundStyle(Color(nsColor: NSColor(hex: 0xC2541B)))
                } else {
                    HStack(spacing: 10) {
                        Text(tr("Talk key not responding?", "说话键没反应？")).font(.system(size: 14)).foregroundStyle(Day.muted)
                        Button(model.state == .listening ? tr("Done", "说完了") : tr("Start here instead", "点这里开始说")) {
                            focused = true
                            Task { await model.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Day.brand)
                    }
                }
                Spacer()
                HStack {
                    Button(tr("Back", "上一步"), action: back).buttonStyle(LinkButtonStyle())
                    Spacer()
                    if succeeded {
                        Button(tr("Try again", "再试一句")) { practice = ""; succeeded = false; focused = true }
                            .buttonStyle(LinkButtonStyle()).padding(.trailing, 14)
                    } else {
                        Button(tr("Skip", "跳过"), action: finish).buttonStyle(LinkButtonStyle()).padding(.trailing, 14)
                    }
                    Button(tr("Start using Speakorb", "开始用"), action: finish)
                        .buttonStyle(DayButtonStyle(primary: succeeded))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 28)
            .padding(.bottom, 22)
        }
        .onAppear { focused = true }
        .onChange(of: model.lastText) { _, newValue in
            guard !newValue.isEmpty else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { succeeded = true }
        }
    }
}
