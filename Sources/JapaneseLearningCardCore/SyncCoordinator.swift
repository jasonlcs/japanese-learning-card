import Foundation

/// 把 push / pull / merge 三件事綁在一起的核心。
/// AppViewModel 只需要 call `pushIfNeeded` / `pullAndMerge` 兩個方法,
/// 不用自己組裝 transport + store + merger + synced base 的協作。
public actor SyncCoordinator {
    public enum SyncError: Error, Sendable, Equatable {
        case transportNotConfigured
        case pushFailed(String)
        case pullFailed(String)
        case mergeFailed(String)
    }

    private let transport: CloudKitTransport
    private let store: AppStore
    private let syncedBase: SyncedBaseStore
    private let conflictStore: ConflictStore
    private let bundleVersion: String
    private let updatedBy: String

    public init(
        transport: CloudKitTransport,
        store: AppStore,
        syncedBase: SyncedBaseStore,
        conflictStore: ConflictStore,
        bundleVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
        updatedBy: String = NSUserName()
    ) {
        self.transport = transport
        self.store = store
        self.syncedBase = syncedBase
        self.conflictStore = conflictStore
        self.bundleVersion = bundleVersion
        self.updatedBy = updatedBy
    }

    /// 讀 local snapshot → 包 payload → 推到雲端, 成功後更新 synced base。
    /// 撞 conflict (雲端有更新版本) 時先 pull+merge 把雲端變更併進來, 再用合併
    /// 後的結果重推一次, 避免直接覆蓋造成資料遺失。
    public func pushIfNeeded() async throws {
        let snapshot = await store.read()
        // 安全網: local 完全沒有使用者內容時不要 push。這可避免本機 DB 因故
        // 開成空檔 (例如過去身分雜湊分檔不穩定的 bug) 時, 把空資料覆蓋掉
        // CloudKit 上既有的資料。空 local 應該靠 pull 還原, 而不是 push 出去。
        if snapshot.isEffectivelyEmpty { return }
        try await pushSnapshot(snapshot, allowMergeRetry: true)
    }

    private func pushSnapshot(_ snapshot: AppSnapshot, allowMergeRetry: Bool) async throws {
        let payload = DatabasePayload(
            bundleVersion: bundleVersion,
            generatedAt: Date(),
            updatedBy: updatedBy,
            snapshot: snapshot
        )

        do {
            try await transport.submit(payload)
        } catch {
            // 撞 conflict: 雲端已有更新版本。先 pull+merge 把遠端變更併進本機,
            // 再用合併後的結果重推一次 (只重試一次, 避免無限迴圈)。
            if allowMergeRetry, Self.isConflict(error) {
                try await pullAndMerge()
                try await pushSnapshot(await store.read(), allowMergeRetry: false)
                return
            }
            throw SyncError.pushFailed(String(describing: error))
        }

        // Push 成功才更新 synced base, 這樣下次的 merge 會以這個為基準。
        do {
            try syncedBase.recordSync(try payload.encoded())
        } catch {
            print("syncedBase write failed after push: \(error)")
        }
    }

    private static func isConflict(_ error: Error) -> Bool {
        guard case CloudKitTransport.TransportError.backing(let backingError) = error else {
            return false
        }
        if case .conflict = backingError { return true }
        return false
    }

    /// 從雲端拉最新一份, 跟 local + synced base 跑 3-way merge,
    /// 把 merged 寫回 local, 衝突寫進 ConflictStore。
    /// 沒 record 就 no-op, 等之後 push。
    public func pullAndMerge() async throws {
        let remote: DatabasePayload
        do {
            guard let fetched = try await transport.fetchLatest() else { return }
            remote = fetched
        } catch {
            throw SyncError.pullFailed(String(describing: error))
        }

        let local = await store.read()
        let base: AppSnapshot? = loadBaseSnapshot()

        let result = Merger.merge3Way(local: local, remote: remote.snapshot, base: base)

        // 寫進 conflict store (即使沒衝突也清空舊的)
        await conflictStore.replace(with: result.conflicts)

        do {
            try await store.update { state in state = result.snapshot }
        } catch {
            throw SyncError.mergeFailed(String(describing: error))
        }

        // Pull 成功後把 remote 當作新的 synced base
        // (pull 後的 local == remote, 所以這代表「兩台現在達到一致」)
        do {
            try syncedBase.recordSync(try remote.encoded())
        } catch {
            print("syncedBase write failed after pull: \(error)")
        }
    }

    private func loadBaseSnapshot() -> AppSnapshot? {
        guard let data = try? syncedBase.loadSync() else { return nil }
        return try? DatabasePayload.decoded(from: data).snapshot
    }
}
