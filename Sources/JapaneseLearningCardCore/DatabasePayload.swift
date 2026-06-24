import Foundation

/// CloudKit record 內的 payload 結構, 包整份 `AppSnapshot`。
///
/// 選擇序列化 `AppSnapshot` 而不是 raw SQLite bytes 是因為:
/// 1. merger 邏輯在 `AppSnapshot` 層跑, 不用 decode SQLite。
/// 2. SQLite 的 binary 格式沒有版控, 之後 migrate 欄位會打亂 sync;
///    AppSnapshot 是 Codable, schema 演化收進 `schemaVersion` 內部。
/// 3. 同步的是「語意層」而不是「儲存層」, debug 也比較好讀。
public struct DatabasePayload: Codable, Sendable, Equatable {
    public static let currentSchemaVersion: Int = 1

    public let schemaVersion: Int
    public let bundleVersion: String
    public let generatedAt: Date
    public let updatedBy: String
    public let snapshot: AppSnapshot

    public init(
        schemaVersion: Int = DatabasePayload.currentSchemaVersion,
        bundleVersion: String,
        generatedAt: Date,
        updatedBy: String,
        snapshot: AppSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.bundleVersion = bundleVersion
        self.generatedAt = generatedAt
        self.updatedBy = updatedBy
        self.snapshot = snapshot
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> DatabasePayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DatabasePayload.self, from: data)
    }
}
