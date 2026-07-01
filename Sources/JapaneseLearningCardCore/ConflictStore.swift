import Foundation

/// 儲存 3-way merge 發現的衝突, 給 UI 顯示跟手動處理。
/// 持久化到 `~/Library/Application Support/JapaneseLearningCard/conflicts.json`,
/// App 重啟後還能查到舊的衝突 (user 跨 session 處理)。
public actor ConflictStore {
    public private(set) var records: [ConflictRecord] = []
    private let storeURL: URL

    public init(storeURL: URL) {
        self.storeURL = storeURL
        // 從磁碟載入舊的 conflicts (非同步的話會讓 init 變麻煩,
        // 反正載入是 sync 讀檔而已, 沒什麼 race)。
        if let data = try? Data(contentsOf: storeURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([ConflictRecord].self, from: data) {
                self.records = decoded
            }
        }
    }

    public func replace(with newRecords: [ConflictRecord]) {
        records = newRecords
        persist()
    }

    public func markResolved(_ id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].isResolved = true
        persist()
    }

    /// 把特定 record 的 resolution 改成 user 選的, 然後 persist。
    /// 實際把值套到 local store 是 AppViewModel 的事 (要走 store.update + push)。
    public func updateResolution(_ id: UUID, to resolution: ConflictRecord.Resolution) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].resolution = resolution
        records[idx].isResolved = true
        persist()
    }

    public func clear() {
        records = []
        persist()
    }

    public var hasUnresolvedConflicts: Bool {
        records.contains { !$0.isResolved }
    }

    public var unresolvedCount: Int {
        records.filter { !$0.isResolved }.count
    }

    public static func defaultURL() -> URL {
        AppPaths.appSupportFolder
            .appendingPathComponent("conflicts.json")
    }

    private func loadFromDisk() {
        // 移到 init 內聯了, 保留這個 private func 避免 warning
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: storeURL)
    }
}
