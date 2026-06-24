import Foundation

/// CloudKit 同步的主要進入點。所有操作都是 async, 會在 transport 的 actor
/// 內序列化, 避免同時多筆 push 撞 CKRecord。
///
/// 主要職責:
/// - 把 `DatabasePayload` 編碼/解碼成 `Data` 走 CloudKit
/// - 樂觀寫入 (帶 expected version) + 撞衝突時 retry 一次
/// - 拿雲端最新一份 (給 pull 用)
/// - 註冊 silent push 訂閱 (給 AppViewModel 啟動時叫一次)
public actor CloudKitTransport {
    public enum TransportError: Error, Sendable, Equatable {
        case backing(CloudKitBackingError)
        case payloadEncodingFailed
        case payloadDecodingFailed
    }

    private let backing: CloudKitBacking
    private let bundleVersion: String
    private let updatedBy: String
    private let maxRetryAttempts = 2

    public init(
        backing: CloudKitBacking,
        bundleVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev",
        updatedBy: String = NSUserName()
    ) {
        self.backing = backing
        self.bundleVersion = bundleVersion
        self.updatedBy = updatedBy
    }

    /// 編碼並上傳。撞衝突自動 retry 一次 (拉新 version 再上傳)。
    public func submit(_ payload: DatabasePayload) async throws {
        let bytes: Data
        do {
            bytes = try payload.encoded()
        } catch {
            throw TransportError.payloadEncodingFailed
        }

        var attempt = 0
        var lastError: Error?
        while attempt < maxRetryAttempts {
            attempt += 1
            do {
                let stored = try await backing.fetchCurrent()
                let expectedVersion = stored?.version
                _ = try await backing.save(payload: bytes, expectedVersion: expectedVersion)
                return
            } catch let error as CloudKitBackingError {
                lastError = error
                if case .conflict = error, attempt < maxRetryAttempts {
                    continue
                }
                throw TransportError.backing(error)
            } catch let error as TransportError {
                throw error
            } catch {
                throw TransportError.backing(.unknown(String(describing: error)))
            }
        }
        if let lastError {
            throw lastError
        }
    }

    /// 拿雲端最新一份, 沒 record 就回 nil。
    public func fetchLatest() async throws -> DatabasePayload? {
        let stored: CloudKitBackingStored?
        do {
            stored = try await backing.fetchCurrent()
        } catch let error as CloudKitBackingError {
            throw TransportError.backing(error)
        } catch {
            throw TransportError.backing(.unknown(String(describing: error)))
        }
        guard let stored else { return nil }
        do {
            return try DatabasePayload.decoded(from: stored.payload)
        } catch {
            throw TransportError.payloadDecodingFailed
        }
    }

    /// 註冊 silent push 訂閱。已經註冊過會自動略過。
    public func ensureSubscriptionRegistered() async throws {
        do {
            try await backing.registerSubscription()
        } catch let error as CloudKitBackingError {
            throw TransportError.backing(error)
        } catch {
            throw TransportError.backing(.unknown(String(describing: error)))
        }
    }

    /// 給 push 觸發 pull 時用的 helper: 拉雲端最新 payload 跟 caller 的 version 比較,
    /// 較新才回傳。Caller 端再決定要不要做 3-way merge。
    public func fetchLatestIfNewer(than currentGeneratedAt: Date) async throws -> DatabasePayload? {
        guard let latest = try await fetchLatest() else { return nil }
        return latest.generatedAt > currentGeneratedAt ? latest : nil
    }
}
