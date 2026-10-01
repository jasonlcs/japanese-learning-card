import Foundation

/// CloudKit V2 schema.  V2 deliberately stores one logical application item
/// per record instead of putting the entire AppSnapshot in one record.
public enum CloudKitV2Schema {
    public static let zoneName = "JapaneseLearningCardV2"
    public static let recordType = "JLCItemV2"
    public static let manifestRecordName = "manifest"
    public static let subscriptionID = "jlc-v2-zone-changes"

    public enum Field: String {
        case kind
        case entityID
        case schemaVersion
        case updatedAt
        case isDeleted
        case payload
        case contentAsset
    }
}

public enum CloudKitV2ItemKind: String, Codable, CaseIterable, Sendable {
    case settings
    case source
    case document
    case card
    case quiz
    case article
}

/// A transport-neutral item.  `assetData` is materialized locally and is
/// converted to CKAsset only by the CloudKit backing implementation.
public struct CloudKitV2Item: Codable, Equatable, Sendable, Identifiable {
    /// Keep ordinary CKRecord fields well below CloudKit's record limit so
    /// metadata growth cannot silently consume the whole record budget.
    public static let maxInlinePayloadBytes = 700_000

    public let kind: CloudKitV2ItemKind
    public let entityID: String
    public let schemaVersion: Int
    public let updatedAt: Date
    public let isDeleted: Bool
    public let payload: Data?
    public let assetData: Data?

    public var id: String {
        Self.recordName(kind: kind, entityID: entityID)
    }

    public init(
        kind: CloudKitV2ItemKind,
        entityID: String,
        schemaVersion: Int = 1,
        updatedAt: Date,
        isDeleted: Bool = false,
        payload: Data? = nil,
        assetData: Data? = nil
    ) {
        self.kind = kind
        self.entityID = entityID
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.payload = payload
        self.assetData = assetData
    }

    public static func recordName(kind: CloudKitV2ItemKind, entityID: String) -> String {
        "jlc-v2:\(kind.rawValue):\(entityID)"
    }
}

public struct CloudKitV2ChangeSet: Sendable, Equatable {
    public let changedItems: [CloudKitV2Item]
    public let deletedRecordNames: [String]
    public let serverChangeToken: Data?

    public init(
        changedItems: [CloudKitV2Item],
        deletedRecordNames: [String] = [],
        serverChangeToken: Data?
    ) {
        self.changedItems = changedItems
        self.deletedRecordNames = deletedRecordNames
        self.serverChangeToken = serverChangeToken
    }
}

public enum CloudKitV2BackingError: Error, Sendable, Equatable {
    case networkUnavailable
    case quotaExceeded
    case notAuthenticated
    case recordTooLarge
    case changeTokenExpired
    case serviceUnavailable(retryAfter: TimeInterval?)
    case rateLimited(retryAfter: TimeInterval?)
    case zoneBusy
    case partialBatchFailure(String)
    case unknown(String)
}

public protocol CloudKitV2Backing: Sendable {
    func ensureZone() async throws
    func fetchChanges(since token: Data?) async throws -> CloudKitV2ChangeSet
    func save(items: [CloudKitV2Item]) async throws
    func registerSubscription() async throws
}
