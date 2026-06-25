import AppKit
import JapaneseLearningCardCore
import SwiftUI

@main
struct JapaneseLearningCardApp {
    static func main() {
        let app = NSApplication.shared
        app.mainMenu = AppMenuFactory.makeMainMenu()
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum AppMenuFactory {
    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit JapaneseLearningCard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var updater: AppUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let store = await AppStore()
            let viewModel = AppViewModel(store: store)
            let controller = MenuBarController(viewModel: viewModel)
            self.menuBarController = controller

            // Sparkle：app 內直接下載／安裝更新。把檢查更新與自動檢查開關
            // 接到 viewModel 的 closure，讓設定頁可以觸發。
            // 本地建置版不啟動 Sparkle，避免從正式 feed 抓到「更新」覆蓋掉開發版。
            if !UpdateChecker.isLocalBuild {
                let updater = AppUpdaterController()
                self.updater = updater
                updater.automaticallyChecksForUpdates =
                    UserDefaults.standard.bool(forKey: UpdateChecker.autoCheckDefaultsKey)
                viewModel.requestCheckForUpdates = { updater.checkForUpdates() }
                viewModel.setAutomaticUpdateChecks = { updater.automaticallyChecksForUpdates = $0 }
            }

            viewModel.start()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    /// 前景時順便拉一次 iCloud。macOS 的 silent push 不可靠, foreground
    /// pull 是「使用者打開 menu bar」這個動作的最直接觸發點。
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await menuBarController?.viewModel.performPull()
        }
    }

    /// iCloud 的 silent push 送過來時叫 AppViewModel 拉一次。
    /// macOS 不保證 background app 一定會醒, 但前景或剛醒的時候通常會送。
    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        Task { @MainActor in
            await menuBarController?.viewModel.performPull()
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    let viewModel: AppViewModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: "Japanese Learning Card")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 520, height: 560)
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = NSHostingController(rootView: RootView(viewModel: viewModel))

        viewModel.requestShowPopover = { [weak self] in
            self?.showPopover()
        }
        viewModel.requestClosePopover = { [weak self] in
            self?.popover.performClose(nil)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.popoverDidShow(isMouseInside: isMouseInsidePopover())
    }

    private func isMouseInsidePopover() -> Bool {
        guard let window = popover.contentViewController?.view.window else {
            return false
        }
        return window.frame.contains(NSEvent.mouseLocation)
    }
}

extension MenuBarController: NSPopoverDelegate {
    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            viewModel.popoverDidClose()
        }
    }
}
