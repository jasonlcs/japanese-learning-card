import Foundation

/// Local-only state for V2.  It is intentionally separate from the user
/// database and is safe to rebuild by fetching the whole custom zone.
public struct CloudKitV2SyncState: Codable, Equatable, Sendable {
    public var remoteItems: [CloudKitV2Item]
    public var baseSnapshot: AppSnapshot?
    public var serverChangeToken: Data?
    public var migrationCompleted: Bool

    public init(
        remoteItems: [CloudKitV2Item] = [],
        baseSnapshot: AppSnapshot? = nil,
        serverChangeToken: Data? = nil,
        migrationCompleted: Bool = false
    ) {
        self.remoteItems = remoteItems
        self.baseSnapshot = baseSnapshot
        self.serverChangeToken = serverChangeToken
        self.migrationCompleted = migrationCompleted
    }
}

public struct CloudKitV2SyncStateStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultURL() -> URL {
        AppPaths.appSupportFolder.appendingPathComponent("cloudkit-v2-state.json")
    }

    public func load() throws -> CloudKitV2SyncState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CloudKitV2SyncState.self, from: data)
    }

    public func save(_ state: CloudKitV2SyncState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url, options: [.atomic])
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
