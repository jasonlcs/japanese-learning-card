import Foundation
import SQLite3

public struct AppSnapshot: Codable, Equatable, Sendable {
    public var settings: AppSettings
    public var sources: [Source]
    public var documents: [CrawledDocument]
    public var cards: [LearningCard]
    public var quizzes: [QuizQuestion]
    public var generatedArticles: [GeneratedArticle]

    public init(
        settings: AppSettings = AppSettings(),
        sources: [Source] = [],
        documents: [CrawledDocument] = [],
        cards: [LearningCard] = [],
        quizzes: [QuizQuestion] = [],
        generatedArticles: [GeneratedArticle] = []
    ) {
        self.settings = settings
        self.sources = sources
        self.documents = documents
        self.cards = cards
        self.quizzes = quizzes
        self.generatedArticles = generatedArticles
    }
}

public actor AppStore {
    private let databaseURL: URL
    private var database: OpaquePointer?
    private var snapshot: AppSnapshot
    private var lastDataVersion: Int64?
    private let stateLock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) async {
        let resolvedURL = fileURL ?? Self.defaultDatabaseURL()
        self.databaseURL = resolvedURL.pathExtension == "json"
            ? resolvedURL.deletingPathExtension().appendingPathExtension("sqlite")
            : resolvedURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        self.snapshot = AppSnapshot()

        do {
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileURL == nil {
                try Self.migrateLegacyDatabaseIfNeeded(to: databaseURL)
            }
            try open()
            try migrate()
            let loaded = try loadSnapshot()
            if loaded == AppSnapshot(), let migrated = try? Self.loadLegacyJSON(near: databaseURL) {
                snapshot = migrated
                try persist()
            } else {
                snapshot = loaded
            }
            lastDataVersion = currentDataVersion()
        } catch {
            snapshot = AppSnapshot()
        }
    }

    public func read() -> AppSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }

        do {
            return try refreshFromDiskIfNeeded()
        } catch {
            print("Failed to reload database from disk at \(databaseURL.path): \(error). This may be resolved by restarting the app or checking iCloud Drive connectivity.")
            return snapshot
        }
    }

    private func refreshFromDiskIfNeeded() throws -> AppSnapshot {
        if hasDatabaseChangedOnDisk() {
            try reloadFromDisk()
        }
        return snapshot
    }

    public func ensureAISentinelSource(extractionPrompt: String) {
        guard !snapshot.sources.contains(where: { $0.id == AISource.sentinelSourceId }) else { return }
        let source = Source(
            id: AISource.sentinelSourceId,
            url: AISource.sentinelURL,
            isEnabled: true,
            extractionPrompt: extractionPrompt
        )
        snapshot.sources.append(source)
        try? persist()
    }

    public func exportableDatabaseURL() -> URL {
        databaseURL
    }

    static let maxUpdateAttempts = 5

    public func update(_ mutate: @Sendable (inout AppSnapshot) -> Void) throws {
        // Optimistic concurrency control for the shared database file:
        //
        // 1. Refresh our in-memory snapshot so the mutation sees the latest data.
        // 2. Apply the mutation to a candidate snapshot.
        // 3. Inside a BEGIN IMMEDIATE write transaction (which holds the write lock),
        //    re-check the SQLite data_version. If another connection committed since
        //    we loaded, abort, reload, re-apply the mutation, and retry. Otherwise
        //    write and COMMIT atomically.
        //
        // Holding the write lock across the version check and the COMMIT closes the
        // TOCTOU window for any writer touching the same file. (Cross-Mac writes via
        // iCloud Drive still can't be fully serialized — that needs a sync backend.)
        for attempt in 1...Self.maxUpdateAttempts {
            if hasDatabaseChangedOnDisk() {
                try reloadFromDisk()
            }
            var candidate = snapshot
            mutate(&candidate)

            do {
                try commitIfUnchanged(candidate)
                snapshot = candidate
                return
            } catch SQLiteStoreError.optimisticConflict {
                if attempt == Self.maxUpdateAttempts {
                    throw SQLiteStoreError.optimisticConflict
                }
                try reloadFromDisk()
            }
        }
    }

    /// 在持有寫鎖的交易中重新確認版本未被其他連線變動，相符才寫入並提交；
    /// 否則回滾並丟出 optimisticConflict 讓呼叫端 reload 後重試。
    private func commitIfUnchanged(_ candidate: AppSnapshot) throws {
        let expected = lastDataVersion
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            if let expected, let current = currentDataVersion(), current != expected {
                throw SQLiteStoreError.optimisticConflict
            }
            try writeSnapshotTables(candidate)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
        // 我們自己的提交不會改變本連線的 data_version，所以重新讀一次作為新的基準。
        lastDataVersion = currentDataVersion()
    }

    private func open() throws {
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw SQLiteStoreError.openFailed(message: lastErrorMessage())
        }
        // 同檔多連線時，BEGIN IMMEDIATE 可能短暫遇到對方持鎖；等待而非立即 SQLITE_BUSY。
        sqlite3_busy_timeout(database, 5000)
    }

    private func hasDatabaseChangedOnDisk() -> Bool {
        // Use SQLite's data_version cookie rather than the file modification date.
        // It reliably changes when *another* connection commits, and stays constant
        // for our own writes. The file mtime was unreliable: its granularity is too
        // coarse to detect near-simultaneous writes from another Mac via iCloud Drive,
        // which silently dropped the other device's changes.
        guard let current = currentDataVersion(), let last = lastDataVersion else {
            return false
        }
        return current != last
    }

    private func currentDataVersion() -> Int64? {
        guard database != nil else { return nil }
        var statement: OpaquePointer?
        do {
            try prepare("PRAGMA data_version;", statement: &statement)
        } catch {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func reloadFromDisk() throws {
        closeDatabase()
        do {
            try open()
            try migrate()
            snapshot = try loadSnapshot()
            lastDataVersion = currentDataVersion()
        } catch {
            lastDataVersion = nil
            throw error
        }
    }

    private func closeDatabase() {
        guard let database else { return }
        let closeResult = sqlite3_close(database)
        if closeResult != SQLITE_OK {
            print("Failed to close database cleanly at \(databaseURL.path): \(closeResult) (\(lastErrorMessage())). This may require restarting the app to avoid stale state.")
            return
        }
        self.database = nil
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS app_state (
            key TEXT PRIMARY KEY NOT NULL,
            json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS sources (
            id TEXT PRIMARY KEY NOT NULL,
            url TEXT NOT NULL,
            is_enabled INTEGER NOT NULL,
            json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS crawled_documents (
            content_hash TEXT PRIMARY KEY NOT NULL,
            source_id TEXT NOT NULL,
            url TEXT NOT NULL,
            fetched_at TEXT NOT NULL,
            json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS learning_cards (
            id TEXT PRIMARY KEY NOT NULL,
            word TEXT NOT NULL,
            status TEXT NOT NULL,
            source_url TEXT NOT NULL,
            json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS quiz_questions (
            id TEXT PRIMARY KEY NOT NULL,
            source_word TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL,
            json TEXT NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS generated_articles (
            id TEXT PRIMARY KEY NOT NULL,
            content_hash TEXT NOT NULL,
            generated_at TEXT NOT NULL,
            json TEXT NOT NULL
        );
        """)
    }

    private func loadSnapshot() throws -> AppSnapshot {
        AppSnapshot(
            settings: try loadState(key: "settings") ?? AppSettings(),
            sources: try loadRows(table: "sources", orderBy: "url"),
            documents: try loadRows(table: "crawled_documents", orderBy: "fetched_at DESC"),
            cards: try loadRows(table: "learning_cards", orderBy: "word"),
            quizzes: try loadRows(table: "quiz_questions", orderBy: "created_at DESC"),
            generatedArticles: try loadRows(table: "generated_articles", orderBy: "generated_at DESC")
        )
    }

    private func persist() throws {
        try execute("BEGIN TRANSACTION;")
        do {
            try writeSnapshotTables(snapshot)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    /// 把整份快照寫入各表(整表覆蓋)。呼叫端負責開啟/提交交易。
    private func writeSnapshotTables(_ snapshot: AppSnapshot) throws {
        try replaceState(key: "settings", value: snapshot.settings)
        try replaceTable("sources", values: snapshot.sources) { source in
            [
                source.id.uuidString,
                source.url.absoluteString,
                source.isEnabled ? "1" : "0",
                try encodeString(source)
            ]
        }
        try replaceTable("crawled_documents", values: snapshot.documents) { document in
            [
                document.contentHash,
                document.sourceId.uuidString,
                document.url.absoluteString,
                Self.iso8601String(from: document.fetchedAt),
                try encodeString(document)
            ]
        }
        try replaceTable("learning_cards", values: snapshot.cards) { card in
            [
                card.id.uuidString,
                card.word,
                card.status.rawValue,
                card.sourceUrl.absoluteString,
                try encodeString(card)
            ]
        }
        try replaceTable("quiz_questions", values: snapshot.quizzes) { quiz in
            [
                quiz.id.uuidString,
                quiz.sourceWord,
                quiz.status.rawValue,
                Self.iso8601String(from: quiz.createdAt),
                try encodeString(quiz)
            ]
        }
        try replaceTable("generated_articles", values: snapshot.generatedArticles) { article in
            [
                article.id.uuidString,
                article.contentHash,
                Self.iso8601String(from: article.generatedAt),
                try encodeString(article)
            ]
        }
    }

    private func loadState<T: Decodable>(key: String) throws -> T? {
        var statement: OpaquePointer?
        try prepare("SELECT json FROM app_state WHERE key = ? LIMIT 1;", statement: &statement)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return try decoder.decode(T.self, from: Data(String(cString: text).utf8))
    }

    private func loadRows<T: Decodable>(table: String, orderBy: String) throws -> [T] {
        var statement: OpaquePointer?
        try prepare("SELECT json FROM \(table) ORDER BY \(orderBy);", statement: &statement)
        defer { sqlite3_finalize(statement) }

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            rows.append(try decoder.decode(T.self, from: Data(String(cString: text).utf8)))
        }
        return rows
    }

    private func replaceState<T: Encodable>(key: String, value: T) throws {
        var statement: OpaquePointer?
        try prepare("INSERT OR REPLACE INTO app_state (key, json) VALUES (?, ?);", statement: &statement)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, try encodeString(value), -1, SQLITE_TRANSIENT)
        try step(statement)
    }

    private func replaceTable<T>(_ table: String, values: [T], columns: (T) throws -> [String]) throws {
        try execute("DELETE FROM \(table);")
        let placeholders: String
        switch table {
        case "sources":
            placeholders = "(id, url, is_enabled, json) VALUES (?, ?, ?, ?)"
        case "crawled_documents":
            placeholders = "(content_hash, source_id, url, fetched_at, json) VALUES (?, ?, ?, ?, ?)"
        case "learning_cards":
            placeholders = "(id, word, status, source_url, json) VALUES (?, ?, ?, ?, ?)"
        case "quiz_questions":
            placeholders = "(id, source_word, status, created_at, json) VALUES (?, ?, ?, ?, ?)"
        case "generated_articles":
            placeholders = "(id, content_hash, generated_at, json) VALUES (?, ?, ?, ?)"
        default:
            throw SQLiteStoreError.invalidTable(table)
        }

        for value in values {
            var statement: OpaquePointer?
            try prepare("INSERT OR REPLACE INTO \(table) \(placeholders);", statement: &statement)
            defer { sqlite3_finalize(statement) }
            let values = try columns(value)
            for (index, value) in values.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
            }
            try step(statement)
        }
    }

    private func encodeString<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastErrorMessage()
            sqlite3_free(error)
            throw SQLiteStoreError.executeFailed(message: message)
        }
    }

    private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteStoreError.executeFailed(message: lastErrorMessage())
        }
    }

    private func step(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteStoreError.executeFailed(message: lastErrorMessage())
        }
    }

    private func lastErrorMessage() -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "Unknown SQLite error."
        }
        return String(cString: message)
    }

    private static func loadLegacyJSON(near databaseURL: URL) throws -> AppSnapshot {
        let jsonURL = databaseURL.deletingPathExtension().appendingPathExtension("json")
        let data = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppSnapshot.self, from: data)
    }

    private static func defaultDatabaseURL() -> URL {
        if let iCloudDatabaseURL = iCloudDriveDatabaseURL() {
            return iCloudDatabaseURL
        }
        return localDatabaseURL()
    }

    private static func localDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("JapaneseLearningCard", isDirectory: true)
            .appendingPathComponent("store.sqlite")
    }

    public static func migrateLegacyDatabaseIfNeeded(to databaseURL: URL, legacyDatabaseURL: URL? = nil) throws {
        guard !FileManager.default.fileExists(atPath: databaseURL.path) else {
            return
        }

        let legacyURL = legacyDatabaseURL ?? localDatabaseURL()
        guard FileManager.default.fileExists(atPath: legacyURL.path) else {
            return
        }

        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: legacyURL, to: databaseURL)
    }

    private static func iCloudDriveDatabaseURL() -> URL? {
        guard let ubiquityContainer = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }

        let appDirectory = ubiquityContainer.appendingPathComponent("Documents/JapaneseLearningCard", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        } catch {
            print("Unable to create the iCloud-backed database directory at \(appDirectory.path): \(error)")
            return nil
        }
        return appDirectory.appendingPathComponent("store.sqlite")
    }

    private static func iso8601String(from date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private enum SQLiteStoreError: LocalizedError {
    case openFailed(message: String)
    case executeFailed(message: String)
    case invalidTable(String)
    case optimisticConflict

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "Unable to open SQLite database: \(message)"
        case .executeFailed(let message):
            "SQLite operation failed: \(message)"
        case .invalidTable(let table):
            "Invalid SQLite table: \(table)"
        case .optimisticConflict:
            "The database changed during the write and could not be reconciled after several attempts."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
