import Foundation

/// 更新相關的輕量輔助。實際的檢查／下載／安裝由 Sparkle 處理
/// （見 `AppUpdaterController`）；這裡只保留版本字串與偏好設定 key，
/// 給設定頁的 UI 使用。
enum UpdateChecker {
    /// 「自動檢查更新」開關存於 UserDefaults，與 Sparkle 的
    /// `automaticallyChecksForUpdates` 橋接（見 AppDelegate）。
    static let autoCheckDefaultsKey = "autoCheckUpdates"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// 是否為本地開發建置。正式發行走 `swift build -c release`（見 build-app.sh），
    /// 不會帶 DEBUG flag；本地 `swift build` / `swift run` 則會。
    /// 本地版不啟動 Sparkle 自動更新，也不檢查更新，避免抓到正式 feed 的版本。
    static var isLocalBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
