import AppKit
import Sparkle

/// 包住 Sparkle 的更新流程：app 內直接下載、驗證、安裝新版並重開，
/// 不再只是把 DMG 連結丟給瀏覽器。
///
/// feed (appcast.xml) 與 EdDSA 公鑰由 Info.plist 的 `SUFeedURL` /
/// `SUPublicEDKey` 提供；更新檔在 release CI 用對應私鑰簽章。
@MainActor
final class AppUpdaterController: NSObject {
    private let updaterController: SPUStandardUpdaterController

    override init() {
        // startingUpdater: true → 啟動時就開始排程自動檢查 (依下方 pref)。
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// 與設定頁「自動檢查更新」開關同步。
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 使用者手動按「立即檢查更新」。即使已是最新版 Sparkle 也會回報。
    func checkForUpdates() {
        // accessory (menu bar) app 沒有 Dock 圖示，先把自己叫到前景，
        // 否則 Sparkle 的更新視窗會被壓在其他 app 後面。
        NSApp.activate(ignoringOtherApps: true)
        updaterController.updater.checkForUpdates()
    }
}
