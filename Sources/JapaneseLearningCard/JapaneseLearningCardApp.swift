import AppKit
import JapaneseLearningCardCore
import JapaneseLearningCardUI
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
            let storageSettings = StorageSettingsStore.load()
            let store = await AppStore(fileURL: UserDataStoreFactory.databaseURL(for: storageSettings))
            let viewModel = AppViewModel(store: store, storageSettings: storageSettings)
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
    private static let popoverWidth: CGFloat = 520

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
        popover.appearance = NSAppearance(named: .aqua)
        // sizingOptions = .preferredContentSize:內容理想高度改變時（換卡、
        // 展開中文翻譯、補注音…）hosting controller 會回報新尺寸，NSPopover
        // 自動跟著調整。否則 popover 只在打開瞬間量一次高度，之後內容變高
        // 就會上下被裁切，最底部的倒數進度條會最先消失。
        let hostingController = NSHostingController(
            rootView: PopoverContentView(viewModel: viewModel, width: Self.popoverWidth)
        )
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        popover.contentSize = preferredPopoverSize()

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
        popover.contentSize = preferredPopoverSize(for: button.window?.screen)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.popoverDidShow(isMouseInside: isMouseInsidePopover())
    }

    private func preferredPopoverSize(for screen: NSScreen? = nil) -> NSSize {
        let visibleHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? 700
        let maximumHeight = floor(visibleHeight * 0.8)
        let measuredHeight = measuredContentHeight(maximumHeight: maximumHeight) ?? maximumHeight
        return NSSize(width: Self.popoverWidth, height: min(ceil(measuredHeight), maximumHeight))
    }

    private func measuredContentHeight(maximumHeight: CGFloat) -> CGFloat? {
        guard let contentView = popover.contentViewController?.view else { return nil }
        let previousFrame = contentView.frame
        contentView.frame = NSRect(
            origin: previousFrame.origin,
            size: NSSize(width: Self.popoverWidth, height: maximumHeight)
        )
        contentView.layoutSubtreeIfNeeded()
        let fittingHeight = contentView.fittingSize.height
        contentView.frame = previousFrame
        return fittingHeight > 0 ? fittingHeight : nil
    }

    private func isMouseInsidePopover() -> Bool {
        guard let window = popover.contentViewController?.view.window else {
            return false
        }
        return window.frame.contains(NSEvent.mouseLocation)
    }
}

/// Popover 內容外框：固定寬度，高度上限取螢幕可視高度的 80%，
/// 讓 preferredContentSize 自動 sizing 不會把 popover 撐出螢幕。
private struct PopoverContentView: View {
    @ObservedObject var viewModel: AppViewModel
    let width: CGFloat

    var body: some View {
        RootView(viewModel: viewModel)
            .frame(width: width)
            .frame(maxHeight: floor((NSScreen.main?.visibleFrame.height ?? 700) * 0.8))
    }
}

extension MenuBarController: NSPopoverDelegate {
    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            viewModel.popoverDidClose()
        }
    }
}
