import XCTest
@testable import JapaneseLearningCardCore

final class CloudKitV2Tests: XCTestCase {
    func testDocumentsAndArticlesUseAssetsAndRoundTrip() throws {
        let sourceID = UUID()
        let articleID = UUID()
        let now = Date(timeIntervalSince1970: 123)
        let source = Source(id: sourceID, url: URL(string: "https://example.com")!, updatedAt: now)
        let document = CrawledDocument(
            sourceId: sourceID,
            url: URL(string: "https://example.com/article")!,
            title: "文件",
            plainText: String(repeating: "日本語の本文。\n", count: 10_000),
            fetchedAt: now,
            contentHash: "document-hash",
            updatedAt: now
        )
        let article = GeneratedArticle(
            id: articleID,
            theme: "旅行",
            jlptLevels: [.n3],
            title: "旅行記事",
            plainText: String(repeating: "旅行の記事です。\n", count: 10_000),
            contentHash: "article-hash",
            sourceId: sourceID,
            generatedAt: now,
            updatedAt: now,
            paragraphs: [ArticleParagraph(japanese: "旅行の記事です。", translation: "這是旅行文章。")]
        )
        var settings = AppSettings()
        settings.updatedAt = now
        let snapshot = AppSnapshot(
            settings: settings,
            sources: [source],
            documents: [document],
            generatedArticles: [article],
            deletedCards: [UUID()]
        )

        let items = try CloudKitV2Codec.items(from: snapshot)
        let documentItem = try XCTUnwrap(items.first { $0.kind == .document })
        let articleItem = try XCTUnwrap(items.first { $0.kind == .article })
        XCTAssertNotNil(documentItem.assetData)
        XCTAssertNotNil(articleItem.assetData)
        XCTAssertLessThan(documentItem.payload?.count ?? .max, document.plainText.utf8.count)
        XCTAssertLessThan(articleItem.payload?.count ?? .max, article.plainText.utf8.count)

        let restored = try CloudKitV2Codec.snapshot(from: items)
        XCTAssertEqual(restored.settings.updatedAt, snapshot.settings.updatedAt)
        XCTAssertEqual(restored.sources, snapshot.sources)
        XCTAssertEqual(restored.documents, snapshot.documents)
        XCTAssertEqual(restored.generatedArticles, snapshot.generatedArticles)
        XCTAssertEqual(restored.deletedCards, snapshot.deletedCards)
    }

    func testRecordNamesAreStableAndNamespaced() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString
        XCTAssertEqual(
            CloudKitV2Item.recordName(kind: .card, entityID: id),
            "jlc-v2:card:\(id)"
        )
        XCTAssertNotEqual(
            CloudKitV2Item.recordName(kind: .card, entityID: id),
            CloudKitV2Item.recordName(kind: .quiz, entityID: id)
        )
    }

    func testSyncStateStoreRoundTripsTokenAndItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = CloudKitV2Item(
            kind: .card,
            entityID: "card-1",
            updatedAt: Date(timeIntervalSince1970: 123),
            payload: Data("{}".utf8)
        )
        var base = AppSnapshot()
        base.settings.updatedAt = Date(timeIntervalSince1970: 123)
        let expected = CloudKitV2SyncState(
            remoteItems: [item],
            baseSnapshot: base,
            serverChangeToken: Data([1, 2, 3]),
            migrationCompleted: true
        )
        let store = CloudKitV2SyncStateStore(url: url)
        try store.save(expected)
        XCTAssertEqual(try store.load(), expected)
    }
}
