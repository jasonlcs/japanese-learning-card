import Foundation

/// CloudKit record 內的 payload 結構, 包整包 SQLite 資料庫。
///
/// CloudKit 的 record schema 改欄位幾乎不可逆, 所以把「schema 演化」收進
/// 這個結構的 `schemaVersion` + `sqliteBytes` 內部, 升級時只 bump 這個
/// 欄位的數字, 對 CloudKit Dashboard 完全無感。
public struct DatabasePayload: Codable, Sendable, Equatable {
    public static let currentSchemaVersion: Int = 1

    public let schemaVersion: Int
    public let bundleVersion: String
    public let generatedAt: Date
    public let updatedBy: String
    public let sqliteBytes: Data

    public init(
        schemaVersion: Int = DatabasePayload.currentSchemaVersion,
        bundleVersion: String,
        generatedAt: Date,
        updatedBy: String,
        sqliteBytes: Data
    ) {
        self.schemaVersion = schemaVersion
        self.bundleVersion = bundleVersion
        self.generatedAt = generatedAt
        self.updatedBy = updatedBy
        self.sqliteBytes = sqliteBytes
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
