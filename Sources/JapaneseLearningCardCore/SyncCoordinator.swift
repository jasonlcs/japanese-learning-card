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
    /// 撞 conflict 由 transport 自動 retry 一次, 這裡只負責 orchestrate。
    public func pushIfNeeded() async throws {
        let snapshot = await store.read()
        let payload = DatabasePayload(
            bundleVersion: bundleVersion,
            generatedAt: Date(),
            updatedBy: updatedBy,
            snapshot: snapshot
        )

        do {
            try await transport.submit(payload)
        } catch {
            throw SyncError.pushFailed(String(describing: error))
        }

        // Push 成功才更新 synced base, 這樣下次的 merge 會以這個為基準。
        do {
            try syncedBase.recordSync(try payload.encoded())
        } catch {
            print("syncedBase write failed after push: \(error)")
        }
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
