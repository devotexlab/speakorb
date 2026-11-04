import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SpeakorbCore

/// 把文字放进当前输入框：优先剪贴板 + ⌘V；安全输入框只复制。
public final class Paster: Injecting {
    public init() {}

    public func inject(_ text: String) async -> InjectionOutcome {
        guard !text.isEmpty else { return InjectionOutcome(method: .failed, message: "empty") }
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotItems(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard !isSecureEventInputEnabled(), AXIsProcessTrusted() else {
            return InjectionOutcome(method: .copyOnly, message: "secure-or-no-access")
        }

        postCommandV()
        try? await Task.sleep(nanoseconds: 350_000_000)
        restore(snapshot, to: pasteboard)
        return InjectionOutcome(method: .paste, message: nil)
    }

    private func isSecureEventInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func snapshotItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
