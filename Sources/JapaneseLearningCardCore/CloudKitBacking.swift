import CloudKit
import Foundation

/// CloudKit transport 用來跟雲端對話的抽象介面。
/// 實作可以是 CKContainer (正式), 也可以是 InMemoryBacking (測試)。
public protocol CloudKitBacking: Sendable {
    /// 抓目前雲端的最新 record。沒有 record 就回 nil。
    func fetchCurrent() async throws -> CloudKitBackingStored?

    /// 樂觀寫入: 帶 `expectedVersion` 跟當前 server 比對, 不符就丟 `conflict`。
    /// `expectedVersion == nil` 表示「無條件覆蓋」(只在首次 push 沒衝突時用)。
    /// 成功回傳新的 version。
    func save(payload: Data, expectedVersion: Int?) async throws -> Int

    /// 註冊 silent push 訂閱。已經註冊過就視為成功。
    func registerSubscription() async throws
}

public struct CloudKitBackingStored: Sendable, Equatable {
    public let payload: Data
    public let version: Int

    public init(payload: Data, version: Int) {
        self.payload = payload
        self.version = version
    }
}

public enum CloudKitBackingError: Error, Sendable, Equatable {
    case conflict(actualVersion: Int)
    case recordNotFound
    case networkUnavailable
    case quotaExceeded
    case notAuthenticated
    case unknown(String)
}

/// 真正的 CloudKit 實作, 把 `CKContainer` 介面翻譯成我們的 protocol。
/// 內部封裝了 fetch + 帶 recordChangeTag + save 的樂觀鎖流程。
public final class CKContainerBacking: CloudKitBacking, @unchecked Sendable {
    private let container: CKContainer
    private let database: CKDatabase
    private let recordID: CKRecord.ID

    public init(
        container: CKContainer = CKContainer(identifier: CloudKitSchema.containerIdentifier),
        recordID: CKRecord.ID = CKRecord.ID(recordName: CloudKitSchema.recordName)
    ) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.recordID = recordID
    }

    public func fetchCurrent() async throws -> CloudKitBackingStored? {
        do {
            let record = try await database.record(for: recordID)
            guard let payload = record[CloudKitSchema.Field.payload.rawValue] as? Data else {
                return nil
            }
            // CloudKit 沒有使用者可讀的 version int, 用 recordChangeTag 的 hash
            // 作為抽象的 version 來偵測衝突。
            let version = Self.version(for: record)
            return CloudKitBackingStored(payload: payload, version: version)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch let error as CKError {
            throw Self.translate(error)
        } catch {
            throw CloudKitBackingError.unknown(String(describing: error))
        }
    }

    public func save(payload: Data, expectedVersion: Int?) async throws -> Int {
        let record: CKRecord
        do {
            let existing = try await database.record(for: recordID)
            if let expectedVersion, Self.version(for: existing) != expectedVersion {
                throw CloudKitBackingError.conflict(actualVersion: Self.version(for: existing))
            }
            record = existing
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CloudKitSchema.recordType, recordID: recordID)
        } catch let error as CKError {
            throw Self.translate(error)
        } catch {
            throw CloudKitBackingError.unknown(String(describing: error))
        }

        record[CloudKitSchema.Field.schemaVersion.rawValue] = NSNumber(value: DatabasePayload.currentSchemaVersion)
        record[CloudKitSchema.Field.bundleVersion.rawValue] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        record[CloudKitSchema.Field.generatedAt.rawValue] = Date() as NSDate
        record[CloudKitSchema.Field.payload.rawValue] = payload as NSData
        record[CloudKitSchema.Field.updatedBy.rawValue] = NSString(string: NSUserName())

        do {
            let saved = try await database.save(record)
            return Self.version(for: saved)
        } catch let error as CKError {
            throw Self.translate(error)
        } catch {
            throw CloudKitBackingError.unknown(String(describing: error))
        }
    }

    public func registerSubscription() async throws {
        // Pelu 的 silent push 訂閱模式: 帶 shouldSendContentAvailable, 不彈通知。
        // macOS 對 silent push 支援不如 iOS 可靠, 仍要靠 foreground poll 兜底,
        // 但訂起來至少 background 有時會醒。
        let subscriptionID = CloudKitSchema.subscriptionID
        if let _ = try? await database.subscription(for: subscriptionID) {
            return
        }
        let subscription = CKQuerySubscription(
            recordType: CloudKitSchema.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.alertBody = nil
        info.shouldBadge = false
        info.soundName = nil
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            return
        } catch let error as CKError where error.code == .invalidArguments {
            // Production container 不允許 client 端建立 query subscription
            // ("attempting to create a subscription in a production container")。
            // macOS 的 silent push 本來就不可靠, 前景輪詢已兜底, 視為正常略過。
            return
        } catch let error as CKError {
            throw Self.translate(error)
        } catch {
            throw CloudKitBackingError.unknown(String(describing: error))
        }
    }

    private static func version(for record: CKRecord) -> Int {
        // CKRecord.recordChangeTag 是 opaque 的 String (例如 "abc123"),
        // 我們用 hash 把它當 int version 來比較, 衝突偵測的可靠性
        // 跟 Pelu 一樣: 任何寫入都會換 tag, 所以 hash 一定會變。
        abs(record.recordChangeTag.hashValue)
    }

    private static func translate(_ error: CKError) -> CloudKitBackingError {
        switch error.code {
        case .serverRecordChanged:
            // 真實的 recordChangeTag 我們拿不到 (CKError 沒暴露), 帶個 sentinel
            // 讓 caller 走 retry 分支; retry 會重新 fetch 拿到正確 version。
            return .conflict(actualVersion: -1)
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .notAuthenticated:
            return .notAuthenticated
        case .unknownItem:
            return .recordNotFound
        default:
            return .unknown(String(describing: error))
        }
    }
}
