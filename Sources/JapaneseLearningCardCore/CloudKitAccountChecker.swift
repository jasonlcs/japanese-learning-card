import CloudKit
import Foundation

/// 把 `CKContainer.accountStatus()` 包成結構化 Result 給 UI 顯示。
/// 借自 Pelu 的設計, 加上一個 short fingerprint 給 onboarding 看
/// 「目前綁定到 _abc123…」這種 iCloud 帳號識別。
public struct CloudKitAccountChecker: Sendable {
    public enum Result: Sendable, Equatable {
        case available
        case noAccount
        case restricted
        case unknown(underlying: String)
        case unexpected(rawValue: Int)
    }

    public struct AccountInfo: Sendable, Equatable {
        public let status: Result
        public let userRecordName: String?

        public init(status: Result, userRecordName: String?) {
            self.status = status
            self.userRecordName = userRecordName
        }
    }

    public init() {}

    public func status(container: CKContainer? = nil) async -> Result {
        let container = container ?? CKContainer(identifier: CloudKitSchema.containerIdentifier)
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine:
                return .unknown(underlying: "couldNotDetermine")
            case .temporarilyUnavailable:
                return .unknown(underlying: "temporarilyUnavailable")
            @unknown default:
                return .unexpected(rawValue: status.rawValue)
            }
        } catch {
            return .unknown(underlying: String(describing: error))
        }
    }

    public func info(container: CKContainer? = nil) async -> AccountInfo {
        let container = container ?? CKContainer(identifier: CloudKitSchema.containerIdentifier)
        let status = await self.status(container: container)
        guard status == .available else {
            return AccountInfo(status: status, userRecordName: nil)
        }
        let recordID = try? await container.userRecordID()
        return AccountInfo(status: status, userRecordName: recordID?.recordName)
    }

    public static func displayFingerprint(_ recordName: String?) -> String? {
        guard let raw = recordName, !raw.isEmpty else { return nil }
        let trimmed = raw.hasPrefix("_") ? String(raw.dropFirst()) : raw
        return String(trimmed.prefix(10)).uppercased()
    }

    public static func displayMessage(for result: Result) -> String {
        switch result {
        case .available:
            return "iCloud 已連線"
        case .noAccount:
            return "請先在系統設定 → Apple ID 登入 iCloud"
        case .restricted:
            return "你的 iCloud 帳號目前被限制 (家長監護或 MDM)"
        case .unknown:
            return "暫時無法連到 iCloud, 稍後再試"
        case .unexpected:
            return "iCloud 回傳未知狀態, 請更新 app 後再試"
        }
    }
}
