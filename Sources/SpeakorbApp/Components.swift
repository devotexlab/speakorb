import AppKit
import SwiftUI
import SpeakorbCore

// MARK: - 声球

/// 品牌符号：就绪时静止发光，听的时候跟音量呼吸，整理时流光旋转，写好后缩成一根光标，没成变橙。
struct VoiceOrb: View {
    enum Phase: Equatable {
        case idle
        case listening
        case writing
        case done
        case error
    }

    var size: CGFloat = 38
    var phase: Phase = .idle
    /// 0…1，只在 listening 时使用。
    var level: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake: CGFloat = 0

    var body: some View {
        ZStack {
            shape
        }
        .frame(width: size, height: size)
        .offset(x: shake)
        .animation(.spring(response: 0.38, dampingFraction: 0.7), value: phase)
        .onChange(of: phase) { _, newValue in
            guard newValue == .error, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.06).repeatCount(5, autoreverses: true)) { shake = 4 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { withAnimation(.easeOut(duration: 0.08)) { shake = 0 } }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var shape: some View {
        switch phase {
        case .writing:
            if reduceMotion {
                Circle().fill(AngularGradient(colors: [.orb2, .orbWarm, .orb1, .orb2], center: .center))
                    .frame(width: size, height: size)
            } else {
                TimelineView(.animation) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360
                    Circle()
                        .fill(AngularGradient(colors: [.orb2, .orbWarm, .orb1, .orb2], center: .center, angle: .degrees(angle)))
                        .frame(width: size, height: size)
                        .shadow(color: Color.orbWarm.opacity(0.55), radius: size * 0.35)
                }
            }
        case .done:
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.ttOK)
                    .frame(width: max(2, size * 0.08), height: size * 0.63)
                    .shadow(color: Color.ttOK.opacity(0.7), radius: 6)
                    .opacity(on ? 1 : 0.15)
            }
        case .error:
            Circle()
                .fill(RadialGradient(
                    colors: [.white, Color(nsColor: NSColor(hex: 0xFFC9A8)), Color(nsColor: NSColor(hex: 0xF07A4A)), Color(nsColor: NSColor(hex: 0x7A2A12))],
                    center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: size * 0.75))
                .frame(width: size, height: size)
                .shadow(color: Color(nsColor: NSColor(hex: 0xF07A4A)).opacity(0.5), radius: size * 0.3)
        case .idle, .listening:
            let l = phase == .listening && !reduceMotion ? min(1, max(0, level)) : 0
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .orb1, location: 0.16),
                        .init(color: .orb2, location: 0.52),
                        .init(color: .orb3, location: 1),
                    ],
                    center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: size * 0.72))
                .frame(width: size, height: size)
                .shadow(color: .orbGlow, radius: size * (0.25 + 0.5 * l))
                .scaleEffect(1 + 0.13 * l)
                .animation(.linear(duration: 0.09), value: l)
        }
    }
}

/// 声球外面一圈圈扩散的光环（空状态、欢迎页用）。
struct OrbRings: View {
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = ((t / 3) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Color.ttAccentRing, lineWidth: 1)
                        .frame(width: size + 32, height: size + 32)
                        .scaleEffect(0.9 + 0.8 * p)
                        .opacity(reduceMotion ? 0.5 : 0.9 * (1 - p))
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// 背景里的一团光。
struct Halo: View {
    var size: CGFloat = 420
    var body: some View {
        RadialGradient(colors: [.ttHalo, .clear], center: .center, startRadius: 0, endRadius: size * 0.31)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }
}

// MARK: - 键帽

struct KeyCap: View {
    let text: String
    var large = false

    var body: some View {
        Text(text)
            .font(.system(size: large ? 14 : 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.ttText)
            .padding(.horizontal, large ? 12 : 6)
            .frame(minWidth: large ? 64 : 24, minHeight: large ? 34 : 20)
            .background(
                RoundedRectangle(cornerRadius: large ? 8 : 5)
                    .fill(Color.ttCard)
                    .shadow(color: Color.black.opacity(0.25), radius: 0, x: 0, y: large ? 3 : 2)
            )
            .overlay(RoundedRectangle(cornerRadius: large ? 8 : 5).strokeBorder(Color.ttLine))
    }
}

// MARK: - 按钮

struct TTButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .secondary

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: kind == .secondary ? .regular : .semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 13)
            .frame(minHeight: 30)
            .foregroundStyle(kind == .secondary ? Color.ttText : Color.white)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(kind == .secondary ? Color.ttLine : .clear)
            )
            .shadow(color: kind == .primary ? Color.ttBrand.opacity(0.35) : .clear, radius: 7, y: 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [.ttBrand, .ttBrand2], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .secondary:
            RoundedRectangle(cornerRadius: 9).fill(Color.ttField)
        case .danger:
            RoundedRectangle(cornerRadius: 9).fill(Color.ttBad)
        }
    }
}

extension ButtonStyle where Self == TTButtonStyle {
    static var ttPrimary: TTButtonStyle { TTButtonStyle(kind: .primary) }
    static var ttSecondary: TTButtonStyle { TTButtonStyle(kind: .secondary) }
    static var ttDanger: TTButtonStyle { TTButtonStyle(kind: .danger) }
}

// MARK: - 标签、分组

struct Pill: View {
    enum Tone { case ok, soon, plain }
    let text: String
    var tone: Tone = .plain

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .foregroundStyle(tone == .ok ? Color.ttOK : tone == .soon ? Color.ttWarn : Color.ttMuted)
            .background(Capsule().fill(tone == .ok ? Color.ttOKSoft : tone == .soon ? Color.ttWarnSoft : Color.ttField))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(Color.ttMuted)
            .padding(.leading, 2)
    }
}

/// 一组带卡片背景的设置行；行与行之间放 RowDivider()。
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.ttCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ttLine))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.ttLine).frame(height: 1)
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(Color.ttText)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Color.ttMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct TTToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(.ttBrand)
            .controlSize(.small)
    }
}

/// 顶部提醒横幅（缺开关等）。
struct AttentionBanner: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void
    var onClose: (() -> Void)?
    var topInset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.ttWarn))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Color.ttMuted)
            }
            Spacer()
            Button(actionTitle, action: action).buttonStyle(.ttPrimary)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.ttSecondary)
                    .accessibilityLabel(tr("Dismiss", "关掉提醒"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.top, topInset)
        .background(Color.ttWarnSoft)
        .overlay(alignment: .bottom) { Divider().overlay(Color.ttLine) }
    }
}

// MARK: - 服务

struct ProviderInfo {
    let id: ProviderID
    let name: String
    let letter: String
    let color: Color
    /// 用这家服务时，录音会不会离开这台 Mac。
    let privacy: String
    let helpURL: URL?

    static var all: [ProviderInfo] { [
        .init(id: .gemini, name: "Gemini", letter: "G", color: Color(nsColor: NSColor(hex: 0x4C7DF0)), privacy: tr("Receives your audio", "录音会发给它"), helpURL: URL(string: "https://aistudio.google.com/app/apikey")),
        .init(id: .openai, name: "OpenAI", letter: "O", color: Color(nsColor: NSColor(hex: 0x10A37F)), privacy: tr("Receives your audio", "录音会发给它"), helpURL: URL(string: "https://platform.openai.com/api-keys")),
        .init(id: .openrouter, name: "OpenRouter", letter: "R", color: Color(nsColor: NSColor(hex: 0x6B5BD6)), privacy: tr("Receives your audio", "录音会发给它"), helpURL: URL(string: "https://openrouter.ai/keys")),
        .init(id: .deepseek, name: "DeepSeek", letter: "D", color: Color(nsColor: NSColor(hex: 0x3B6FE0)), privacy: tr("Receives text only, no audio", "只收文字，不收录音"), helpURL: URL(string: "https://platform.deepseek.com/api_keys")),
        .init(id: .bailian, name: tr("Bailian", "百炼"), letter: tr("B", "百"), color: Color(nsColor: NSColor(hex: 0xFF6A00)), privacy: tr("Receives your audio", "录音会发给它"), helpURL: URL(string: "https://bailian.console.aliyun.com/")),
        .init(id: .custom, name: tr("Custom service", "自定义服务"), letter: "⋯", color: Color(nsColor: NSColor(hex: 0x8A8F98)), privacy: tr("Depends on your service", "看你的服务"), helpURL: nil),
    ] }

    static func of(_ id: ProviderID) -> ProviderInfo? { all.first { $0.id == id } }

    static func displayName(_ id: ProviderID) -> String {
        id == .local ? tr("On-device dictation", "本机听写") : (of(id)?.name ?? id.rawValue)
    }
}

struct ProviderLogo: View {
    let info: ProviderInfo
    var size: CGFloat = 24
    var body: some View {
        Text(info.letter)
            .font(.system(size: size * 0.46, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.29).fill(info.color))
    }
}

// MARK: - 小工具

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// 按时长画几根竖条，示意这一段说了多久。
struct DurationBars: View {
    let durationMs: Int
    let seed: Int

    var body: some View {
        HStack(spacing: 2) {
            let count = max(4, min(40, durationMs / 160))
            ForEach(0..<count, id: \.self) { k in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.ttAccent.opacity(0.55))
                    .frame(width: 2, height: 3 + abs(sin(Double(k) * 1.7 + Double(seed % 7))) * 8)
            }
        }
        .frame(height: 11)
        .accessibilityHidden(true)
    }
}
