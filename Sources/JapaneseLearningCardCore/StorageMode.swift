import Foundation

public enum StorageMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case localOnly
    case iCloudDriveFolder
    case cloudKit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .localOnly: "Local Only"
        case .iCloudDriveFolder: "iCloud Drive Folder"
        case .cloudKit: "CloudKit"
        }
    }
}

public struct StorageSettings: Codable, Equatable, Sendable {
    public var mode: StorageMode
    public var localDataPath: String?
    public var iCloudDriveFolderPath: String?
    public var cloudKitContainerId: String?

    public init(
        mode: StorageMode = .cloudKit,
        localDataPath: String? = nil,
        iCloudDriveFolderPath: String? = nil,
        cloudKitContainerId: String? = nil
    ) {
        self.mode = mode
        self.localDataPath = localDataPath
        self.iCloudDriveFolderPath = iCloudDriveFolderPath
        self.cloudKitContainerId = cloudKitContainerId
    }
}

public struct DataStoreHealth: Equatable, Sendable {
    public var isWritable: Bool
    public var message: String
    public var location: URL

    public init(isWritable: Bool, message: String, location: URL) {
        self.isWritable = isWritable
        self.message = message
        self.location = location
    }
}

public protocol UserDataStore: Sendable {
    func loadSnapshot() async throws -> AppSnapshot
    func saveSnapshot(_ snapshot: AppSnapshot) async throws
    func getHealth() async throws -> DataStoreHealth
    func databaseURL() async -> URL
}

public struct SQLiteUserDataStore: UserDataStore {
    private let store: AppStore
    private let location: URL

    public init(store: AppStore, location: URL) {
        self.store = store
        self.location = location
    }

    public func loadSnapshot() async throws -> AppSnapshot {
        await store.read()
    }

    public func saveSnapshot(_ snapshot: AppSnapshot) async throws {
        try await store.replaceSnapshot(snapshot)
    }

    public func getHealth() async throws -> DataStoreHealth {
        let directory = location.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = directory.appendingPathComponent(".write-test-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .atomic)
            try? FileManager.default.removeItem(at: probe)
            return DataStoreHealth(isWritable: true, message: "可寫入", location: location)
        } catch {
            return DataStoreHealth(isWritable: false, message: error.localizedDescription, location: location)
        }
    }

    public func databaseURL() async -> URL {
        location
    }
}

public enum StorageSettingsStore {
    private static let key = "JapaneseLearningCard.storageSettings.v1"

    public static func load(defaults: UserDefaults = .standard) -> StorageSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(StorageSettings.self, from: data) else {
            return StorageSettings(mode: .cloudKit)
        }
        return settings
    }

    public static func save(_ settings: StorageSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

public enum UserDataStoreFactory {
    public static func databaseURL(for settings: StorageSettings) -> URL {
        switch settings.mode {
        case .localOnly:
            if let path = settings.localDataPath, !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("store.sqlite")
            }
            return AppStore.localDatabaseURL()
        case .iCloudDriveFolder:
            if let path = settings.iCloudDriveFolderPath, !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("store.sqlite")
            }
            return defaultICloudDriveFolder().appendingPathComponent("store.sqlite")
        case .cloudKit:
            return AppStore.localDatabaseURL()
        }
    }

    public static func create(settings: StorageSettings) async -> SQLiteUserDataStore {
        let url = databaseURL(for: settings)
        let store = await AppStore(fileURL: url)
        return SQLiteUserDataStore(store: store, location: url)
    }

    public static func defaultLocalFolder() -> URL {
        AppStore.localDatabaseURL().deletingLastPathComponent()
    }

    public static func defaultICloudDriveFolder() -> URL {
#if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            .appendingPathComponent("JapaneseLearningCard", isDirectory: true)
#else
        AppPaths.appSupportFolder
            .appendingPathComponent("iCloudDriveFolder", isDirectory: true)
#endif
    }

    public static func appearsInsideICloudDrive(_ folder: URL) -> Bool {
        folder.standardizedFileURL.path.contains("/Library/Mobile Documents/com~apple~CloudDocs/")
    }
}
