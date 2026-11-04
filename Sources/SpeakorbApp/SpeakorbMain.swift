import SwiftUI
import AppKit
import Combine

@main
struct SpeakorbMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            Image(systemName: model.menuIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var floatingBar: FloatingBarController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        NSApp.setActivationPolicy(model.showInDock ? .regular : .accessory)
        NSApp.appearance = model.theme.appearance
        floatingBar = FloatingBarController(model: model)

        model.$theme
            .sink { NSApp.appearance = $0.appearance }
            .store(in: &cancellables)
        model.$language
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.window?.title = tr("Speakorb", "声球") }
            .store(in: &cancellables)
        model.$showInDock
            .dropFirst()
            .sink { [weak self] show in
                NSApp.setActivationPolicy(show ? .regular : .accessory)
                if show { self?.showMainWindow() }
            }
            .store(in: &cancellables)
        model.$onboardingComplete
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.layoutWindow() }
            .store(in: &cancellables)

        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        model.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func showMainWindow(section: AppModel.Section? = nil) {
        if let section { AppModel.shared.section = section }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: RootView().environmentObject(AppModel.shared))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = tr("Speakorb", "声球")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SpeakorbMain")
        self.window = window
        layoutWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 引导是固定大小的日光窗口；主窗口 940×640，可以拉大，最小 760×520。
    private func layoutWindow() {
        guard let window else { return }
        if AppModel.shared.onboardingComplete {
            window.appearance = nil
            window.styleMask.insert(.resizable)
            window.contentMinSize = NSSize(width: 760, height: 520)
            if window.frame.width < 900 {
                window.setContentSize(NSSize(width: 940, height: 640))
                window.center()
            }
        } else {
            window.appearance = NSAppearance(named: .aqua)
            window.styleMask.remove(.resizable)
            window.contentMinSize = NSSize(width: 720, height: 560)
            window.setContentSize(NSSize(width: 720, height: 560))
            window.center()
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel

    private func open(_ section: AppModel.Section? = nil) {
        (NSApp.delegate as? AppDelegate)?.showMainWindow(section: section)
    }

    var body: some View {
        if let missing = model.missingSwitch {
            Button(tr("One more step: \(missing.title)", "还差一步：\(missing.title)")) { missing.open() }
        } else {
            Text(tr("Speakorb · \(model.statusTitle)", "声球 · \(model.statusTitle)"))
        }
        if model.state == .listening {
            Button(tr("Done", "说完了")) { Task { await model.toggle() } }
            Button(tr("Cancel", "取消")) { model.cancel() }
        }
        Divider()
        Button(tr("Open Speakorb", "打开声球")) { open() }
        Button(tr("History", "说过的话")) { open(.records) }
        Button(tr("Custom words", "常用词")) { open(.terms) }
        Divider()
        Button(model.paused ? tr("Resume", "继续听写") : tr("Pause dictation", "暂停听写")) { model.paused.toggle() }
        Button(tr("Help & feedback", "帮助与反馈")) { open(.help) }
        Button(tr("Settings…", "设置…")) { open(.settings(.general)) }
            .keyboardShortcut(",")
        Divider()
        Button(tr("Quit Speakorb", "退出声球")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
