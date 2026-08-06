import Foundation

/// Converts the local semantic model into CloudKit V2 items.  Large textual
/// bodies are deliberately kept out of the normal CKRecord fields.
public enum CloudKitV2Codec {
    private static let schemaVersion = 1

    private struct DocumentMetadata: Codable {
        let sourceId: UUID
        let url: URL
        let title: String
        let fetchedAt: Date
        let contentHash: String
        let updatedAt: Date
    }

    private struct ArticleMetadata: Codable {
        let id: UUID
        let kind: GeneratedArticleKind
        let theme: String
        let jlptLevels: [JLPTLevel]
        let title: String
        let contentHash: String
        let sourceId: UUID
        let generatedAt: Date
        let cardCount: Int
        let updatedAt: Date
        let userPrompt: String?
        let vocabularySource: String?
        let vocabularyWords: [String]?
    }

    private struct ArticleContent: Codable {
        let plainText: String
        let paragraphs: [ArticleParagraph]?
        let titleRuby: [RubySegment]?
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    public static func items(from snapshot: AppSnapshot) throws -> [CloudKitV2Item] {
        var result: [CloudKitV2Item] = []
        result.append(CloudKitV2Item(
            kind: .settings,
            entityID: "settings",
            schemaVersion: schemaVersion,
            updatedAt: snapshot.settings.updatedAt,
            payload: try encode(snapshot.settings)
        ))

        result += try snapshot.sources.map {
            CloudKitV2Item(kind: .source, entityID: $0.id.uuidString, schemaVersion: schemaVersion, updatedAt: $0.updatedAt, payload: try encode($0))
        }
        result += try snapshot.documents.map { document in
            CloudKitV2Item(
                kind: .document,
                entityID: document.contentHash,
                schemaVersion: schemaVersion,
                updatedAt: document.updatedAt,
                payload: try encode(DocumentMetadata(
                    sourceId: document.sourceId,
                    url: document.url,
                    title: document.title,
                    fetchedAt: document.fetchedAt,
                    contentHash: document.contentHash,
                    updatedAt: document.updatedAt
                )),
                assetData: Data(document.plainText.utf8)
            )
        }
        result += try snapshot.cards.map {
            CloudKitV2Item(kind: .card, entityID: $0.id.uuidString, schemaVersion: schemaVersion, updatedAt: $0.updatedAt, payload: try encode($0))
        }
        result += try snapshot.quizzes.map {
            CloudKitV2Item(kind: .quiz, entityID: $0.id.uuidString, schemaVersion: schemaVersion, updatedAt: $0.updatedAt, payload: try encode($0))
        }
        result += try snapshot.generatedArticles.map { article in
            CloudKitV2Item(
                kind: .article,
                entityID: article.id.uuidString,
                schemaVersion: schemaVersion,
                updatedAt: article.updatedAt,
                payload: try encode(ArticleMetadata(
                    id: article.id,
                    kind: article.kind,
                    theme: article.theme,
                    jlptLevels: article.jlptLevels,
                    title: article.title,
                    contentHash: article.contentHash,
                    sourceId: article.sourceId,
                    generatedAt: article.generatedAt,
                    cardCount: article.cardCount,
                    updatedAt: article.updatedAt,
                    userPrompt: article.userPrompt,
                    vocabularySource: article.vocabularySource,
                    vocabularyWords: article.vocabularyWords
                )),
                assetData: try encode(ArticleContent(
                    plainText: article.plainText,
                    paragraphs: article.paragraphs,
                    titleRuby: article.titleRuby
                ))
            )
        }

        // AppSnapshot does not retain deletion timestamps.  A stable epoch is
        // used so an unchanged tombstone is not re-uploaded on every push;
        // the existing 3-way merge treats tombstones as set membership.
        let tombstoneDate = Date(timeIntervalSince1970: 0)
        result += snapshot.deletedSources.map { CloudKitV2Item(kind: .source, entityID: $0.uuidString, schemaVersion: schemaVersion, updatedAt: tombstoneDate, isDeleted: true) }
        result += snapshot.deletedDocuments.map { CloudKitV2Item(kind: .document, entityID: $0, schemaVersion: schemaVersion, updatedAt: tombstoneDate, isDeleted: true) }
        result += snapshot.deletedCards.map { CloudKitV2Item(kind: .card, entityID: $0.uuidString, schemaVersion: schemaVersion, updatedAt: tombstoneDate, isDeleted: true) }
        result += snapshot.deletedQuizzes.map { CloudKitV2Item(kind: .quiz, entityID: $0.uuidString, schemaVersion: schemaVersion, updatedAt: tombstoneDate, isDeleted: true) }
        result += snapshot.deletedArticles.map { CloudKitV2Item(kind: .article, entityID: $0.uuidString, schemaVersion: schemaVersion, updatedAt: tombstoneDate, isDeleted: true) }

        return result
    }

    public static func snapshot(from items: [CloudKitV2Item]) throws -> AppSnapshot {
        var settings = AppSettings()
        var sources: [Source] = []
        var documents: [CrawledDocument] = []
        var cards: [LearningCard] = []
        var quizzes: [QuizQuestion] = []
        var articles: [GeneratedArticle] = []
        var deletedSources: [UUID] = []
        var deletedDocuments: [String] = []
        var deletedCards: [UUID] = []
        var deletedQuizzes: [UUID] = []
        var deletedArticles: [UUID] = []

        for item in items {
            if item.isDeleted {
                switch item.kind {
                case .settings: break
                case .source: if let id = UUID(uuidString: item.entityID) { deletedSources.append(id) }
                case .document: deletedDocuments.append(item.entityID)
                case .card: if let id = UUID(uuidString: item.entityID) { deletedCards.append(id) }
                case .quiz: if let id = UUID(uuidString: item.entityID) { deletedQuizzes.append(id) }
                case .article: if let id = UUID(uuidString: item.entityID) { deletedArticles.append(id) }
                }
                continue
            }

            guard let payload = item.payload else { continue }
            switch item.kind {
            case .settings:
                settings = try decode(AppSettings.self, from: payload)
            case .source:
                sources.append(try decode(Source.self, from: payload))
            case .document:
                let metadata = try decode(DocumentMetadata.self, from: payload)
                guard let assetData = item.assetData,
                      let plainText = String(data: assetData, encoding: .utf8) else {
                    throw NSError(domain: "JapaneseLearningCard.CloudKitV2", code: 1, userInfo: [NSLocalizedDescriptionKey: "文件同步內容遺失"])
                }
                documents.append(CrawledDocument(
                    sourceId: metadata.sourceId,
                    url: metadata.url,
                    title: metadata.title,
                    plainText: plainText,
                    fetchedAt: metadata.fetchedAt,
                    contentHash: metadata.contentHash,
                    updatedAt: metadata.updatedAt
                ))
            case .card:
                cards.append(try decode(LearningCard.self, from: payload))
            case .quiz:
                quizzes.append(try decode(QuizQuestion.self, from: payload))
            case .article:
                let metadata = try decode(ArticleMetadata.self, from: payload)
                guard let assetData = item.assetData else {
                    throw NSError(domain: "JapaneseLearningCard.CloudKitV2", code: 2, userInfo: [NSLocalizedDescriptionKey: "文章同步內容遺失"])
                }
                let content = try decode(ArticleContent.self, from: assetData)
                articles.append(GeneratedArticle(
                    id: metadata.id,
                    kind: metadata.kind,
                    theme: metadata.theme,
                    jlptLevels: metadata.jlptLevels,
                    title: metadata.title,
                    plainText: content.plainText,
                    contentHash: metadata.contentHash,
                    sourceId: metadata.sourceId,
                    generatedAt: metadata.generatedAt,
                    cardCount: metadata.cardCount,
                    updatedAt: metadata.updatedAt,
                    paragraphs: content.paragraphs,
                    userPrompt: metadata.userPrompt,
                    vocabularySource: metadata.vocabularySource,
                    vocabularyWords: metadata.vocabularyWords,
                    titleRuby: content.titleRuby
                ))
            }
        }

        return AppSnapshot(
            settings: settings,
            sources: sources,
            documents: documents,
            cards: cards,
            quizzes: quizzes,
            generatedArticles: articles,
            deletedSources: deletedSources,
            deletedDocuments: deletedDocuments,
            deletedCards: deletedCards,
            deletedQuizzes: deletedQuizzes,
            deletedArticles: deletedArticles
        )
    }
}
