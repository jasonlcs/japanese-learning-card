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
}
