import AppKit
import Foundation

/// 透過 GitHub Releases API 檢查是否有新版本，並引導使用者下載 DMG。
/// 偏好設定（是否自動檢查、上次檢查時間）存於 UserDefaults，與資料庫設定獨立。
struct UpdateChecker {
    static let shared = UpdateChecker()

    private let repo = "jasonlcs/japanese-learning-card"
    private let appDisplayName = "日本語學習卡"

    static let autoCheckDefaultsKey = "autoCheckUpdates"
    private static let lastCheckDefaultsKey = "lastUpdateCheck"

    /// 在跳出任何 alert 前呼叫，讓選單列 popover 先收起、app 移到前景，
    /// 避免 alert 被仍浮在上層的 transient popover 蓋住。由 MenuBarController 設定。
    @MainActor static var prepareToPresentAlert: (() -> Void)?

    struct Release: Codable {
        let tagName: String
        let htmlUrl: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case assets
        }
    }

    struct Asset: Codable {
        let name: String
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Public API

    /// 手動檢查。showUpToDate 為 true 時，即使已是最新版也會跳出提示。
    func checkForUpdates(showUpToDate: Bool = false) async {
        let latest = await fetchLatestRelease()
        await MainActor.run {
            handleUpdateResult(latest, showUpToDate: showUpToDate)
        }
    }

    /// 啟動時自動檢查：需開啟自動檢查、且距離上次檢查超過一小時，且有更新才會跳出。
    func autoCheckIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.autoCheckDefaultsKey) else { return }
        let lastCheck = Date(timeIntervalSince1970: defaults.double(forKey: Self.lastCheckDefaultsKey))
        guard Date().timeIntervalSince(lastCheck) > 3600 else { return }
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastCheckDefaultsKey)

        let latest = await fetchLatestRelease()
        guard let release = latest, isNewer(release.tagName, than: currentVersion) else { return }
        await MainActor.run {
            showUpdateAlert(release: release)
        }
    }

    // MARK: - Private

    private func fetchLatestRelease() async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            return try JSONDecoder().decode(Release.self, from: data)
        } catch {
            return nil
        }
    }

    private func isNewer(_ tagName: String, than current: String) -> Bool {
        let latest = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        return latest.compare(current, options: .numeric) == .orderedDescending
    }

    @MainActor
    private func handleUpdateResult(_ release: Release?, showUpToDate: Bool) {
        guard let release else {
            showAlert(title: "檢查更新失敗", message: "無法連線至 GitHub，請稍後再試。")
            return
        }
        if isNewer(release.tagName, than: currentVersion) {
            showUpdateAlert(release: release)
        } else if showUpToDate {
            showAlert(title: "已是最新版本", message: "\(appDisplayName) \(currentVersion) 是目前最新版本。")
        }
    }

    @MainActor
    private func showUpdateAlert(release: Release) {
        Self.prepareToPresentAlert?()
        let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
        let downloadURL = dmgAsset?.browserDownloadUrl ?? release.htmlUrl

        let alert = NSAlert()
        alert.messageText = "有新版本可用"
        alert.informativeText = "\(appDisplayName) \(release.tagName) 已發佈（目前版本 \(currentVersion)）。\n是否前往下載？"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "下載")
        alert.addButton(withTitle: "稍後")
        alert.icon = NSImage(named: NSImage.applicationIconName)

        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: downloadURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        Self.prepareToPresentAlert?()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
