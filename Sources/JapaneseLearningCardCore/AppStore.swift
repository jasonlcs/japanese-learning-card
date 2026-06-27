import Foundation
import SQLite3

public struct AppSnapshot: Codable, Equatable, Sendable {
    public var settings: AppSettings
    public var sources: [Source]
    public var documents: [CrawledDocument]
    public var cards: [LearningCard]
    public var quizzes: [QuizQuestion]
    public var generatedArticles: [GeneratedArticle]

    /// Soft-delete tombstones, 用 UUID / contentHash 標記已刪除的 record。
    /// AppStore.update 自動偵測 closure 裡刪掉的 record 並推進這裡,
    /// 跨 Mac 的刪除才會被 merge 帶過去。record 本身不在 `sources` /
    /// `cards` 等陣列裡, 這些陣列永遠是 live 狀態, UI 不用過濾。
    public var deletedSources: [UUID]
    public var deletedDocuments: [String]
    public var deletedCards: [UUID]
    public var deletedQuizzes: [UUID]
    public var deletedArticles: [UUID]

    public init(
        settings: AppSettings = AppSettings(),
        sources: [Source] = [],
        documents: [CrawledDocument] = [],
        cards: [LearningCard] = [],
        quizzes: [QuizQuestion] = [],
        generatedArticles: [GeneratedArticle] = [],
        deletedSources: [UUID] = [],
        deletedDocuments: [String] = [],
        deletedCards: [UUID] = [],
        deletedQuizzes: [UUID] = [],
        deletedArticles: [UUID] = []
    ) {
        self.settings = settings
        self.sources = sources
        self.documents = documents
        self.cards = cards
        self.quizzes = quizzes
        self.generatedArticles = generatedArticles
        self.deletedSources = deletedSources
        self.deletedDocuments = deletedDocuments
        self.deletedCards = deletedCards
        self.deletedQuizzes = deletedQuizzes
        self.deletedArticles = deletedArticles
    }

    /// 沒有任何使用者內容（只可能有預設的 sentinel source、沒有任何 tombstone）。
    /// 用來當「不要把空資料 push 上雲端覆蓋」的安全網判斷。
    public var isEffectivelyEmpty: Bool {
        cards.isEmpty
            && quizzes.isEmpty
            && generatedArticles.isEmpty
            && documents.isEmpty
            && deletedSources.isEmpty
            && deletedDocuments.isEmpty
            && deletedCards.isEmpty
            && deletedQuizzes.isEmpty
            && deletedArticles.isEmpty
            && sources.allSatisfy(AISource.isSentinelSource)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        self.sources = try container.decodeIfPresent([Source].self, forKey: .sources) ?? []
        self.documents = try container.decodeIfPresent([CrawledDocument].self, forKey: .documents) ?? []
        self.cards = try container.decodeIfPresent([LearningCard].self, forKey: .cards) ?? []
        self.quizzes = try container.decodeIfPresent([QuizQuestion].self, forKey: .quizzes) ?? []
        self.generatedArticles = try container.decodeIfPresent([GeneratedArticle].self, forKey: .generatedArticles) ?? []
        // 舊版 snapshot 沒有 deleted* 欄位, decode 時預設空陣列 (向後相容)
        self.deletedSources = try container.decodeIfPresent([UUID].self, forKey: .deletedSources) ?? []
        self.deletedDocuments = try container.decodeIfPresent([String].self, forKey: .deletedDocuments) ?? []
        self.deletedCards = try container.decodeIfPresent([UUID].self, forKey: .deletedCards) ?? []
        self.deletedQuizzes = try container.decodeIfPresent([UUID].self, forKey: .deletedQuizzes) ?? []
        self.deletedArticles = try container.decodeIfPresent([UUID].self, forKey: .deletedArticles) ?? []
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

    /// 當資料庫被外部替換成功後觸發 (例如 CloudKit pull 把遠端 bytes
    /// 寫進來, 或測試強制 reload)。設為 nil 可取消監聽。callback 跑在
    /// 背景 actor 上, UI 更新需自行切到 MainActor。
    private var onExternalChange: (@Sendable () -> Void)?

    public func setOnExternalChange(_ callback: (@Sendable () -> Void)?) {
        onExternalChange = callback
    }

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
                try Self.migrateIdentityScopedStoreIfNeeded(to: databaseURL)
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

    /// 強制關閉並重新開啟資料庫連線，重新讀取整份 snapshot。
    /// 給測試或外部工具用。
    public func forceReloadFromDisk() throws {
        try reloadFromDisk()
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
        do {
            try update { state in
                if let index = state.sources.firstIndex(where: AISource.isSentinelSource) {
                    let existing = state.sources[index]
                    state.sources[index] = Source(
                        id: AISource.sentinelSourceId,
                        url: AISource.sentinelURL,
                        isEnabled: false,
                        extractionPrompt: extractionPrompt.isEmpty ? existing.extractionPrompt : extractionPrompt,
                        lastFetchedAt: existing.lastFetchedAt,
                        lastError: nil
                    )
                    return
                }

                state.sources.append(Source(
                    id: AISource.sentinelSourceId,
                    url: AISource.sentinelURL,
                    isEnabled: false,
                    extractionPrompt: extractionPrompt
                ))
            }
        } catch {
            print("ensureAISentinelSource failed: \(error)")
        }
    }

    public func exportableDatabaseURL() -> URL {
        databaseURL
    }

    public func replaceSnapshot(_ newSnapshot: AppSnapshot) throws {
        snapshot = newSnapshot
        try persist()
        lastDataVersion = currentDataVersion()
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
            let before = snapshot
            var candidate = snapshot
            mutate(&candidate)
            Self.applyDeletions(before: before, after: &candidate)
            Self.stampUpdatedAt(before: before, after: &candidate)

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

    /// 自動偵測 closure 裡刪掉的 record, 推進對應的 `deleted*` 清單。
    /// 雙向處理:
    /// - `before` 有 / `after` 沒有的 ID → 加進 deleted 清單 (soft delete)
    /// - `before` 沒 / `after` 有的 ID, 且原本在 deleted 清單 → 從清單移除 (un-delete)
    /// 跨 Mac 的刪除才能透過 merge 帶到另一台。
    private static func applyDeletions(before: AppSnapshot, after: inout AppSnapshot) {
        // Sources
        let beforeSourceIDs = Set(before.sources.map { $0.id })
        let afterSourceIDs = Set(after.sources.map { $0.id })
        var deletedSources = Set(after.deletedSources)
        deletedSources.formUnion(beforeSourceIDs.subtracting(afterSourceIDs))
        deletedSources.subtract(afterSourceIDs.subtracting(beforeSourceIDs))
        after.deletedSources = Array(deletedSources)

        // Documents (keyed by contentHash)
        let beforeDocHashes = Set(before.documents.map { $0.contentHash })
        let afterDocHashes = Set(after.documents.map { $0.contentHash })
        var deletedDocs = Set(after.deletedDocuments)
        deletedDocs.formUnion(beforeDocHashes.subtracting(afterDocHashes))
        deletedDocs.subtract(afterDocHashes.subtracting(beforeDocHashes))
        after.deletedDocuments = Array(deletedDocs)

        // Cards
        let beforeCardIDs = Set(before.cards.map { $0.id })
        let afterCardIDs = Set(after.cards.map { $0.id })
        var deletedCards = Set(after.deletedCards)
        deletedCards.formUnion(beforeCardIDs.subtracting(afterCardIDs))
        deletedCards.subtract(afterCardIDs.subtracting(beforeCardIDs))
        after.deletedCards = Array(deletedCards)

        // Quizzes
        let beforeQuizIDs = Set(before.quizzes.map { $0.id })
        let afterQuizIDs = Set(after.quizzes.map { $0.id })
        var deletedQuizzes = Set(after.deletedQuizzes)
        deletedQuizzes.formUnion(beforeQuizIDs.subtracting(afterQuizIDs))
        deletedQuizzes.subtract(afterQuizIDs.subtracting(beforeQuizIDs))
        after.deletedQuizzes = Array(deletedQuizzes)

        // Articles
        let beforeArticleIDs = Set(before.generatedArticles.map { $0.id })
        let afterArticleIDs = Set(after.generatedArticles.map { $0.id })
        var deletedArticles = Set(after.deletedArticles)
        deletedArticles.formUnion(beforeArticleIDs.subtracting(afterArticleIDs))
        deletedArticles.subtract(afterArticleIDs.subtracting(beforeArticleIDs))
        after.deletedArticles = Array(deletedArticles)
    }

    /// 對「實際被改動」的 record 戳上 `updatedAt = Date()`, 沒動到的保留原值。
    /// Merger 靠這個欄位判斷 LWW 與偵測衝突, 所以必須在 persist 之前設定。
    private static func stampUpdatedAt(before: AppSnapshot, after: inout AppSnapshot) {
        let now = Date()
        if before.settings != after.settings {
            after.settings.updatedAt = now
        }
        stampRecords(before: before.sources, after: &after.sources, key: \.id, now: now)
        stampRecords(before: before.documents, after: &after.documents, key: \.contentHash, now: now)
        stampRecords(before: before.cards, after: &after.cards, key: \.id, now: now)
        stampRecords(before: before.quizzes, after: &after.quizzes, key: \.id, now: now)
        stampRecords(before: before.generatedArticles, after: &after.generatedArticles, key: \.id, now: now)
    }

    private static func stampRecords<T: MergeTrackable>(
        before: [T],
        after: inout [T],
        key: KeyPath<T, UUID>,
        now: Date
    ) {
        let oldById = Dictionary(uniqueKeysWithValues: before.map { ($0[keyPath: key], $0) })
        for index in after.indices {
            let recordID = after[index][keyPath: key]
            if let oldRecord = oldById[recordID], oldRecord == after[index] {
                after[index].updatedAt = oldRecord.updatedAt
            } else {
                after[index].updatedAt = now
            }
        }
    }

    private static func stampRecords<T: MergeTrackable>(
        before: [T],
        after: inout [T],
        key: KeyPath<T, String>,
        now: Date
    ) {
        let oldById = Dictionary(uniqueKeysWithValues: before.map { ($0[keyPath: key], $0) })
        for index in after.indices {
            let recordID = after[index][keyPath: key]
            if let oldRecord = oldById[recordID], oldRecord == after[index] {
                after[index].updatedAt = oldRecord.updatedAt
            } else {
                after[index].updatedAt = now
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
            generatedArticles: try loadRows(table: "generated_articles", orderBy: "generated_at DESC"),
            deletedSources: try loadState(key: "deletedSources") ?? [],
            deletedDocuments: try loadState(key: "deletedDocuments") ?? [],
            deletedCards: try loadState(key: "deletedCards") ?? [],
            deletedQuizzes: try loadState(key: "deletedQuizzes") ?? [],
            deletedArticles: try loadState(key: "deletedArticles") ?? []
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
        try replaceState(key: "deletedSources", value: snapshot.deletedSources)
        try replaceState(key: "deletedDocuments", value: snapshot.deletedDocuments)
        try replaceState(key: "deletedCards", value: snapshot.deletedCards)
        try replaceState(key: "deletedQuizzes", value: snapshot.deletedQuizzes)
        try replaceState(key: "deletedArticles", value: snapshot.deletedArticles)
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

    public static func defaultDatabaseURL() -> URL {
        // 走 CloudKit payload 同步後, 本機就是唯一來源, 直接用本地路徑。
        return localDatabaseURL()
    }

    /// 本機 DB 路徑。統一用 store.sqlite —— 不再依「iCloud 身分雜湊」分檔，
    /// 因為那個雜湊 (ubiquityIdentityToken 封存後取 hash) 並不穩定，會害每次
    /// 啟動開到不同的空檔，造成資料看似被清空、甚至把空檔 push 上 CloudKit
    /// 覆蓋雲端。帳號隔離交給 CloudKit（雲端本就分帳號）+ 3-way merge。
    public static func localDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("JapaneseLearningCard", isDirectory: true)
            .appendingPathComponent("store.sqlite")
    }

    /// 從舊版「依 iCloud 身分雜湊分檔」(store-<hash>.sqlite) 遷移到統一的
    /// store.sqlite。挑資料最完整（檔案最大）的一份複製過來，避免升級後從空白
    /// 開始。只在 store.sqlite 還不存在時做一次；排除 synced base (store-synced.sqlite)。
    public static func migrateIdentityScopedStoreIfNeeded(to canonicalURL: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: canonicalURL.path) else { return }
        let directory = canonicalURL.deletingLastPathComponent()
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }
        let scoped = entries.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("store-")
                && name.hasSuffix(".sqlite")
                && name != "store-synced.sqlite"
        }
        guard let best = scoped.max(by: { fileByteSize($0) < fileByteSize($1) }) else { return }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.copyItem(at: best, to: canonicalURL)
    }

    private static func fileByteSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
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
