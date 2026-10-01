import XCTest
import SQLite3
@testable import JapaneseLearningCardCore

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class AppStoreDateBackfillTests: XCTestCase {
    func testAppStoreAutoBackfillsMissingCardDateAndPersistsToSQLite() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("test.sqlite")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. 手動建立資料庫並塞入一筆沒有 createdAt 的老資料
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        let createTableSQL = """
        CREATE TABLE app_state (key TEXT PRIMARY KEY NOT NULL, json TEXT NOT NULL);
        CREATE TABLE sources (id TEXT PRIMARY KEY NOT NULL, url TEXT NOT NULL, is_enabled INTEGER NOT NULL, json TEXT NOT NULL);
        CREATE TABLE crawled_documents (content_hash TEXT PRIMARY KEY NOT NULL, source_id TEXT NOT NULL, url TEXT NOT NULL, fetched_at TEXT NOT NULL, json TEXT NOT NULL);
        CREATE TABLE learning_cards (id TEXT PRIMARY KEY NOT NULL, word TEXT NOT NULL, status TEXT NOT NULL, source_url TEXT NOT NULL, json TEXT NOT NULL);
        CREATE TABLE quiz_questions (id TEXT PRIMARY KEY NOT NULL, source_word TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, json TEXT NOT NULL);
        CREATE TABLE generated_articles (id TEXT PRIMARY KEY NOT NULL, content_hash TEXT NOT NULL, generated_at TEXT NOT NULL, json TEXT NOT NULL);
        """
        XCTAssertEqual(sqlite3_exec(db, createTableSQL, nil, nil, nil), SQLITE_OK)

        let oldCardId = "11111111-2222-3333-4444-555555555555"
        let oldJsonWithoutCreatedAt = """
        {
          "id": "\(oldCardId)",
          "word": "試験",
          "reading": "しけん",
          "partOfSpeech": "名詞",
          "meaningZh": "考試",
          "grammarNoteZh": "",
          "exampleJa": "試験を受ける",
          "exampleZh": "參加考試",
          "sourceUrl": "https://example.com",
          "status": "new",
          "shownCount": 2,
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """

        var insertStmt: OpaquePointer?
        let insertSQL = "INSERT INTO learning_cards (id, word, status, source_url, json) VALUES (?, ?, ?, ?, ?);"
        XCTAssertEqual(sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil), SQLITE_OK)
        sqlite3_bind_text(insertStmt, 1, oldCardId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insertStmt, 2, "試験", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insertStmt, 3, "new", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insertStmt, 4, "https://example.com", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insertStmt, 5, oldJsonWithoutCreatedAt, -1, SQLITE_TRANSIENT)
        XCTAssertEqual(sqlite3_step(insertStmt), SQLITE_DONE)
        sqlite3_finalize(insertStmt)
        sqlite3_close(db)

        // 2. 初始化 AppStore
        let store = await AppStore(fileURL: dbURL)
        let snapshot = await store.read()

        XCTAssertEqual(snapshot.cards.count, 1)
        let card = snapshot.cards[0]
        XCTAssertEqual(card.word, "試験")

        let todayString = LearningCard.createdDateFormatter.string(from: Date())
        XCTAssertEqual(card.formattedCreatedAt, todayString)

        // 3. 關閉 store，直接查 SQLite 確認 raw json 是否已經持久化更新
        var checkDb: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &checkDb), SQLITE_OK)
        var selectStmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(checkDb, "SELECT json FROM learning_cards WHERE id = ?;", -1, &selectStmt, nil), SQLITE_OK)
        sqlite3_bind_text(selectStmt, 1, oldCardId, -1, SQLITE_TRANSIENT)
        XCTAssertEqual(sqlite3_step(selectStmt), SQLITE_ROW)
        guard let rawText = sqlite3_column_text(selectStmt, 0) else {
            XCTFail("Missing json column")
            return
        }
        let persistedJson = String(cString: rawText)
        sqlite3_finalize(selectStmt)
        sqlite3_close(checkDb)

        XCTAssertTrue(persistedJson.contains("createdAt"), "Persisted JSON must contain createdAt")
        XCTAssertFalse(persistedJson.contains("1970-01-01"), "Persisted JSON must not be 1970")
    }
}
