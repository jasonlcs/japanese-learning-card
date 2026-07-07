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
    /// 最近一次在本 App 內的點擊／鍵盤／捲動時間。onHover 在捲動、視窗
    /// 高度變動、開選單時常誤報「滑鼠已離開」，倒數會在使用者操作到一半
    /// 恢復；這個訊號直接記錄「真的有人在操作」，比 hover 可靠。
    private var lastUserInputAt: Date = .distantPast
    private var inputMonitor: Any?
    /// 最近有輸入的這段時間內視為操作中，不自動收回 popover。
    private static let recentInputWindow: TimeInterval = 15

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
        // popover 尺寸只有一個來源：sizingOptions = .preferredContentSize。
        // 內容理想高度改變時（換卡、展開中文翻譯、補注音…）hosting controller
        // 回報新尺寸，NSPopover 自動跟著調整。不要再手動量 fittingSize 設
        // contentSize——兩個來源互相干擾會讓 popover 每開一次就縮一點。
        let hostingController = NSHostingController(
            rootView: PopoverContentView(viewModel: viewModel, width: Self.popoverWidth)
        )
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController

        viewModel.requestShowPopover = { [weak self] in
            self?.showPopover()
        }
        viewModel.requestClosePopover = { [weak self] in
            self?.popover.performClose(nil)
        }
        viewModel.isPopoverBusy = { [weak self] in
            self?.isPopoverBusy() ?? false
        }

        // 本 App 唯一的 UI 就是這個 popover（加上它的 sheet／面板），
        // local monitor 只收得到自家視窗的事件，等於「使用者正在操作」。
        inputMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            self?.lastUserInputAt = Date()
            return event
        }
    }

    /// 「忙碌」= 不可以自動收回 popover：掛著 sheet（文章預覽等）、有 modal
    /// 面板（匯出／選資料夾）、正在打字、滑鼠就在 popover 上、或最近幾秒內
    /// 有任何點擊／鍵盤輸入。在這些時機收掉 popover 除了打斷操作，sheet／
    /// modal 的呈現狀態還會殘留在已消失的視窗上，下次打開整個 UI 點不了。
    private func isPopoverBusy() -> Bool {
        if Date().timeIntervalSince(lastUserInputAt) < Self.recentInputWindow { return true }
        if NSApp.modalWindow != nil { return true }
        guard let window = popover.contentViewController?.view.window else { return false }
        if window.attachedSheet != nil { return true }
        if window.isKeyWindow, window.firstResponder is NSTextView { return true }
        return window.frame.contains(NSEvent.mouseLocation)
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
        // 上次若在 sheet 開著時被關掉，sheet 會殘留並攔走所有滑鼠事件，
        // 讓重開後的 popover 完全點不動。開之前先把殘留的 sheet 收掉。
        if let window = popover.contentViewController?.view.window,
           let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
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
    /// sheet 或 modal 面板（匯出／選資料夾）開著時一律不准關——transient
    /// 的點外面（點到 sheet／面板本身也算「外面」）、倒數到期的 performClose
    /// 都會先走到這。在它們底下把 popover 收掉會讓呈現狀態卡死，重開後
    /// 整個 popover 點不了任何東西。
    nonisolated func popoverShouldClose(_ popover: NSPopover) -> Bool {
        MainActor.assumeIsolated {
            popover.contentViewController?.view.window?.attachedSheet == nil
                && NSApp.modalWindow == nil
        }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            viewModel.popoverDidClose()
        }
    }
}
