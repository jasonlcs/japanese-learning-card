import Foundation

/// 儲存最近一次 3-way merge 發現的衝突, 給 UI 顯示紅點。
/// 單純的 in-memory 儲存, App 重啟就清空 (使用者下次 pull 會重新抓到)。
public actor ConflictStore {
    public private(set) var records: [ConflictRecord] = []

    public init() {}

    public func replace(with newRecords: [ConflictRecord]) {
        records = newRecords
    }

    public func clear() {
        records = []
    }

    public var hasUnresolvedConflicts: Bool { !records.isEmpty }
}
