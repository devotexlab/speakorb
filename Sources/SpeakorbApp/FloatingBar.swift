import AppKit
import Combine
import SwiftUI
import SpeakorbCore

/// 悬浮条：不抢焦点的面板，出现在鼠标所在屏幕的底部正中。
@MainActor
final class FloatingBarController {
    private let model: AppModel
    private let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    private var cancellables: Set<AnyCancellable> = []
    private var hideWork: DispatchWorkItem?

    init(model: AppModel) {
        self.model = model
        hosting = NSHostingView(rootView: AnyView(FloatingBarView().environmentObject(model)))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = hosting

        model.$hud
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in self?.update(phase) }
            .store(in: &cancellables)
    }

    private func update(_ phase: AppModel.HUDPhase?) {
        hideWork?.cancel()
        guard let phase else {
            // 等 SwiftUI 的收起动画播完再藏面板。
            let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
            return
        }
        // 只有“没成”有可以点的按钮；其他状态鼠标直接穿过去。
        if case .error = phase {
            panel.ignoresMouseEvents = false
        } else {
            panel.ignoresMouseEvents = true
        }
        if !panel.isVisible { place() }
        panel.orderFrontRegardless()
    }

    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 40))
    }
}

/// 悬浮条本身。面板固定 520×120，透明，条子贴底居中。
struct FloatingBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let phase = model.hud {
                FloatingBarCard(phase: phase, level: model.level, startedAt: model.listeningStartedAt, lastText: model.lastText,
                                onRetry: { model.dismissHUD(); Task { await model.toggle() } },
                                onClose: { model.dismissHUD() })
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 520, height: 120)
        .id(model.language)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.hud)
    }
}

struct FloatingBarCard: View {
    let phase: AppModel.HUDPhase
    var level: Double = 0
    var startedAt: Date?
    var lastText: String = ""
    var onRetry: () -> Void = {}
    var onClose: () -> Void = {}

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 14) {
            VoiceOrb(size: 38, phase: orbPhase, level: level)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 10) {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(labelColor)
                    if case .listening = phase, let startedAt {
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            Text(TTDate.duration(ms: Int(context.date.timeIntervalSince(startedAt) * 1000)))
                                .font(.ttMono(11))
                                .foregroundStyle(Color.ttMuted)
                        }
                    }
                }
                Text(message)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.ttText)
                    .lineLimit(phase.isError ? 2 : 1)
                    .truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.leading, 11)
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .frame(width: phase == .done ? 300 : 460)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .background(RoundedRectangle(cornerRadius: 24).fill(scheme == .dark ? Color(nsColor: NSColor(hex: 0x10101C, alpha: 0.78)) : Color.white.opacity(0.82)))
        )
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.ttAccentRing.opacity(scheme == .dark ? 0.8 : 0.5)))
        .shadow(color: Color.orbGlow.opacity(scheme == .dark ? 0.35 : 0.18), radius: 22)
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)，\(message)")
    }

    private var orbPhase: VoiceOrb.Phase {
        switch phase {
        case .listening: return .listening
        case .writing: return .writing
        case .done: return .done
        case .error(let e): return e.isCopyOnly ? .idle : .error
        }
    }

    private var label: String {
        switch phase {
        case .listening: return tr("● LISTENING", "● 正在听")
        case .writing: return tr("◌ TIDYING UP", "◌ 正在整理")
        case .done: return tr("✓ DONE", "✓ 写好了")
        case .error(let e): return e.isCopyOnly ? tr("COPIED", "已复制") : tr("DIDN'T WORK", "这次没成")
        }
    }

    private var labelColor: Color {
        switch phase {
        case .listening: return .ttRec
        case .writing: return .ttWarn
        case .done: return .ttOK
        case .error(let e): return e.isCopyOnly ? .ttAccent : .ttWarn
        }
    }

    private var message: String {
        switch phase {
        case .listening: return tr("Press right ⌥ when you're done · esc to cancel", "说完按右 ⌥，esc 取消")
        case .writing: return tr("Turning what you said into text…", "正在把你说的话整理成字…")
        case .done: return lastText.isEmpty ? tr("Put into the text field", "已放进输入框") : lastText
        case .error(let e): return e.isCopyOnly ? tr("Press ⌘V to paste; this field doesn't accept typing", "按 ⌘V 粘贴；这个地方不让直接放字") : e.localizedMessage
        }
    }

    @ViewBuilder private var trailing: some View {
        switch phase {
        case .listening:
            Text("esc")
                .font(.ttMono(11))
                .foregroundStyle(Color.ttMuted)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.ttLine))
        case .error(let e):
            HStack(spacing: 6) {
                if !e.isCopyOnly {
                    Button(tr("Try again", "重说"), action: onRetry).buttonStyle(.ttPrimary)
                }
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.ttSecondary)
                    .accessibilityLabel(tr("Close", "关掉"))
            }
        case .writing, .done:
            EmptyView()
        }
    }
}

extension AppModel.HUDPhase {
    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

extension SpeakorbError {
    /// 字没放进去但已经复制好了：这不算失败，用提示语气。
    var isCopyOnly: Bool {
        if case .injectionFailed = self { return true }
        return false
    }
}
