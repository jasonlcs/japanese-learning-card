import Foundation

/// 持久化「上次成功同步到 iCloud 的 snapshot」當作 3-way merge 的 common base。
///
/// 寫入時機：每次 AppStore 把 snapshot 成功 push 上去之後, 把當下的 bytes
/// 存到 `synced.sqlite`。 pull 時用它做 diff。
///
/// 不在 main thread 跑: SQLite 寫入可能會 block, 但這支只在背景 transport
/// 內被呼叫, 沒人會去 await 它。
public struct SyncedBaseStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// 預設路徑: `~/Library/Application Support/JapaneseLearningCard/store-synced.sqlite`
    public static func defaultURL() -> URL {
        AppPaths.appSupportFolder
            .appendingPathComponent("store-synced.sqlite")
    }

    /// 寫入或覆蓋 synced base。寫入是 atomic: 先寫到 `.tmp` 再 rename。
    public func recordSync(_ bytes: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        try bytes.write(to: tmp, options: [.atomic])
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    /// 讀取 synced base, 沒有就回 nil。
    public func loadSync() throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
