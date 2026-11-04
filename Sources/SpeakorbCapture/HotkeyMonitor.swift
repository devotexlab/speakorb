import Foundation
import CoreGraphics
import SpeakorbCore

/// 全局热键：轻点右 Option 切换录音；Esc 取消。
/// 需要"辅助功能"或"输入监控"权限。
public final class HotkeyMonitor: HotkeyMonitoring {
    public private(set) var isRunning = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var optionDown = false
    private var onToggle: (() -> Void)?
    private var onCancel: (() -> Void)?

    private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        monitor.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    private let rightOptionKeyCode: Int64 = 61
    private let escapeKeyCode: Int64 = 53

    public init() {}

    public func start(onToggle: @escaping () -> Void, onCancel: @escaping () -> Void) throws {
        guard !isRunning else { return }
        self.onToggle = onToggle
        self.onCancel = onCancel
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: HotkeyMonitor.eventCallback,
            userInfo: refcon
        ) else {
            throw SpeakorbError.inputMonitoringPermission
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged, keyCode == rightOptionKeyCode {
            let down = event.flags.contains(.maskAlternate)
            if down && !optionDown {
                optionDown = true
                if let onToggle { DispatchQueue.main.async(execute: onToggle) }
            } else if !down && optionDown {
                optionDown = false
            }
            return
        }
        if type == .keyDown, keyCode == escapeKeyCode {
            if let onCancel { DispatchQueue.main.async(execute: onCancel) }
        }
    }
}
