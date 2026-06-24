import Foundation

/// CloudKit 同步用的固定常數。要在 Apple Developer Portal 建立對應的
/// container (iCloud.io.github.jasonlcs.japaneselearningcard), 並在 App ID
/// 開啟 CloudKit capability。
public enum CloudKitSchema {
    /// CloudKit container ID, 必須與 Apple Developer Portal 上建立的 container
    /// 一致。
    public static let containerIdentifier = "iCloud.io.github.jasonlcs.japaneselearningcard"

    /// 整包 SQLite 資料庫的 record type。整個 app 只放一筆這個 type 的 record。
    public static let recordType = "AppDatabase"

    /// 固定 record name, 確保每次 push 都更新同一筆而非新增。
    public static let recordName = "database"

    /// `CKQuerySubscription` 的固定 ID, 重新註冊時會自動更新既有的。
    public static let subscriptionID = "app-database-changes-v1"

    public enum Field: String {
        case schemaVersion
        case bundleVersion
        case generatedAt
        case payload
        case updatedBy
    }
}
