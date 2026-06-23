import Foundation
import JapaneseLearningCardCore

@main
struct CoreChecks {
    static func main() async throws {
        try sourceValidatorAcceptsHTTPAndHTTPS()
        try sourceValidatorBlocksSSRF()
        schedulerClampsIntervals()
        cardSelectorPrioritizesFreshThenOldestReviewingAndSkipsSkipped()
        htmlExtractorRemovesScriptsStylesTagsAndDecodesEntities()
        try openAICompatibleRequestAndCardDecoding()
        try exampleReadingDecoding()
        try await pipelineRefreshesEnabledSourcesWithMocks()
        try await storePersistsQuizQuestions()
        try await storeMigratesLegacyDatabaseWhenNeeded()
        try await storeReloadsFromDiskWhenDatabaseChangesExternally()
        try aiArticleRequestAndDecoding()
        try await pipelineGeneratesAIArticleAndCards()
        try await storePersistsGeneratedArticles()
        print("All JapaneseLearningCardCore checks passed.")
    }

    private static func sourceValidatorAcceptsHTTPAndHTTPS() throws {
        let validator = SourceValidator()
        try validator.validate(URL(string: "https://example.com/article")!)
        try validator.validate(URL(string: "http://example.com/article")!)

        expectThrows {
            try validator.validate(URL(string: "file:///tmp/article.html")!)
        }
        expectThrows {
            try validator.validate(URL(string: "https:///missing-host")!)
        }
    }

    private static func sourceValidatorBlocksSSRF() throws {
        let validator = SourceValidator()
        let blockedHosts = [
            "http://127.0.0.1/admin",
            "http://localhost:6379",
            "http://10.0.0.5/secret",
            "http://172.16.0.1/private",
            "http://192.168.1.1/router",
            "http://169.254.169.254/latest/meta-data/",
            "http://[::1]/",
            "http://224.0.0.1/multicast"
        ]
        for raw in blockedHosts {
            let url = URL(string: raw)!
            expectThrows {
                try validator.validate(url)
            }
        }
        try validator.validate(URL(string: "https://news.yahoo.co.jp/")!)
    }

    private static func schedulerClampsIntervals() {
        let policy = SchedulerPolicy()
        let settings = AppSettings(displayIntervalMinutes: 0, visibleDurationSeconds: 1, crawlIntervalHours: 0)

        expect(policy.displayInterval(settings: settings) == 60, "display interval should clamp to 60 seconds")
        expect(policy.visibleDuration(settings: settings) == 3, "visible duration should clamp to 3 seconds")
        expect(policy.crawlInterval(settings: settings) == 3600, "crawl interval should clamp to 1 hour")
    }

    private static func cardSelectorPrioritizesFreshThenOldestReviewingAndSkipsSkipped() {
        let selector = CardSelector()
        let url = URL(string: "https://example.com")!
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 200)
        let skipped = card("飛ばす", status: .skipped, createdAt: old, lastShownAt: nil, url: url)
        let reviewingRecent = card("最近", status: .reviewing, createdAt: old, lastShownAt: recent, url: url)
        let fresh = card("新しい", status: .new, createdAt: recent, lastShownAt: nil, url: url)

        expect(selector.nextCard(from: [skipped, reviewingRecent, fresh])?.word == "新しい", "fresh new card should be selected first")

        let reviewingOld = card("古い", status: .reviewing, createdAt: old, lastShownAt: old, url: url)
        expect(selector.nextCard(from: [skipped, reviewingRecent, reviewingOld])?.word == "古い", "oldest reviewing card should be selected")

        let learned = card("学習済み", status: .learned, createdAt: old, lastShownAt: old, url: url)
        expect(selector.nextCard(from: [skipped, learned]) == nil, "learned cards should not be selected")
    }

    private static func htmlExtractorRemovesScriptsStylesTagsAndDecodesEntities() {
        let html = """
        <html><head><title>日本語 &amp; 学習</title><style>.x{}</style></head>
        <body><script>alert(1)</script><article>今日は&nbsp;いい天気です。</article></body></html>
        """

        let result = HTMLTextExtractor().extract(html: html)

        expect(result.title == "日本語 & 学習", "title should be decoded")
        expect(result.text.contains("今日は いい天気です。"), "body text should remain")
        expect(!result.text.contains("alert"), "scripts should be removed")
        expect(!result.text.contains(".x"), "styles should be removed")
    }

    private static func openAICompatibleRequestAndCardDecoding() throws {
        let document = CrawledDocument(
            sourceId: UUID(),
            url: URL(string: "https://example.com")!,
            title: "記事",
            plainText: "今日は駅で友達に会いました。",
            contentHash: "hash"
        )
        let settings = AppSettings(providerConfig: ProviderConfig(baseURL: URL(string: "https://api.example.test/v1")!, model: "custom-model"))

        let body = OpenAICompatibleLLMClient.requestBody(document: document, sourcePrompt: "駅に関する単語", settings: settings)
        expect(body.model == "custom-model", "request should use configured model")
        expect(body.messages.last?.content.contains("駅に関する単語") == true, "request should include extraction prompt")
        expect(body.messages.last?.content.contains("今日は駅で友達に会いました。") == true, "request should include document text")

        let cards = try OpenAICompatibleLLMClient.decodeCards(from: """
        {"cards":[{"word":"駅","reading":"えき","partOfSpeech":"名詞","meaningZh":"車站","grammarNoteZh":"地點名詞。","jlptLevel":"N4","verbFormType":"非動詞","exampleJa":"駅で会います。","exampleReading":"えきであいます。","exampleZh":"在車站見面。"},{"word":"水","reading":"みず","partOfSpeech":"名詞","meaningZh":"水","grammarNoteZh":"基本名詞。","jlptLevel":"N5","verbFormType":"非動詞","exampleJa":"水を飲みます。","exampleReading":"みずをのみます。","exampleZh":"喝水。"}]}
        """, sourceURL: document.url)

        expect(cards.count == 1, "one card should decode")
        expect(cards[0].word == "駅", "word should decode")
        expect(cards[0].jlptLevel == .n4, "JLPT level should decode")
        expect(cards[0].verbFormType == .notVerb, "non-verb form should decode")
        expect(cards[0].exampleReading == "えきであいます。", "example reading should decode")
        expect(cards[0].sourceUrl == document.url, "source URL should be attached")
    }

    private static func exampleReadingDecoding() throws {
        let reading = try OpenAICompatibleLLMClient.decodeExampleReading(from: #"{"exampleReading":"かれはちゅうごくごをべんきょうしています。"}"#)
        expect(reading == "かれはちゅうごくごをべんきょうしています。", "example reading payload should decode")
    }

    private static func pipelineRefreshesEnabledSourcesWithMocks() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.json")
        let store = await AppStore(fileURL: fileURL)
        let source = Source(url: URL(string: "https://example.com/article")!)
        try await store.update { state in
            state.sources = [source]
        }

        let pipeline = LearningPipeline(
            store: store,
            crawler: MockCrawler(document: CrawledDocument(
                sourceId: source.id,
                url: source.url,
                title: "Mock",
                plainText: "電車に乗ります。",
                contentHash: "mock-hash"
            )),
            llmClient: MockLLMClient(cardURL: source.url)
        )

        await pipeline.refreshEnabledSources()
        let snapshot = await store.read()

        expect(snapshot.documents.count == 1, "document should be stored")
        expect(snapshot.cards.count == 1, "card should be stored")
        expect(snapshot.cards[0].word == "電車", "mock card should be stored")
        expect(snapshot.sources[0].lastError == nil, "source should have no error")
        expect(snapshot.sources[0].lastFetchedAt != nil, "source fetch date should be set")
    }

    private static func storePersistsQuizQuestions() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        let quiz = QuizQuestion(
            sourceWord: "駅",
            question: "「駅」の意味は？",
            choices: ["車站", "學校", "公司", "公園"],
            correctAnswer: "車站",
            explanationZh: "駅是車站。"
        )
        try await store.update { state in
            state.quizzes = [quiz]
        }

        let reloaded = await AppStore(fileURL: fileURL)
        let snapshot = await reloaded.read()
        expect(snapshot.quizzes.count == 1, "quiz should persist in SQLite")
        expect(snapshot.quizzes[0].question == "「駅」の意味は？", "quiz question should round trip")
    }

    private static func storeMigratesLegacyDatabaseWhenNeeded() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let legacyDatabaseURL = tempDirectory.appendingPathComponent("legacy.sqlite")
        let targetDatabaseURL = tempDirectory.appendingPathComponent("target.sqlite")
        try Data("legacy-db".utf8).write(to: legacyDatabaseURL)

        try AppStore.migrateLegacyDatabaseIfNeeded(to: targetDatabaseURL, legacyDatabaseURL: legacyDatabaseURL)
        expect(FileManager.default.fileExists(atPath: targetDatabaseURL.path), "target database should exist")

        try AppStore.migrateLegacyDatabaseIfNeeded(to: targetDatabaseURL, legacyDatabaseURL: legacyDatabaseURL)
        expect(FileManager.default.fileExists(atPath: targetDatabaseURL.path), "migration should be idempotent")
    }

    private static func storeReloadsFromDiskWhenDatabaseChangesExternally() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        try await store.update { state in
            state.settings.displayIntervalMinutes = 5
        }

        let initialModificationDate = try fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let externalStore = await AppStore(fileURL: fileURL)
        try await externalStore.update { state in
            state.settings.displayIntervalMinutes = 17
        }

        let updatedModificationDate = try fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        expect(updatedModificationDate != nil, "database file should receive a new modification date")
        expect(initialModificationDate != updatedModificationDate, "database file should change when another writer updates it")

        let snapshot = await store.read()
        expect(snapshot.settings.displayIntervalMinutes == 17, "store should reload from disk when another writer updates the database")
    }

    private static func aiArticleRequestAndDecoding() throws {
        let settings = AppSettings(providerConfig: ProviderConfig(baseURL: URL(string: "https://api.example.test/v1")!, model: "custom-model"))

        let body = OpenAICompatibleLLMClient.articleRequestBody(theme: "旅行", jlptLevels: [.n3, .n2], settings: settings)
        expect(body.model == "custom-model", "article request should use configured model")
        expect(body.messages.last?.content.contains("旅行") == true, "article request should include theme")
        expect(body.messages.last?.content.contains("N2") == true, "article request should list JLPT levels")
        expect(body.messages.first?.content.contains("N5") == true, "system prompt should mention N5 guidance when not requested")

        let compactBody = OpenAICompatibleLLMClient.articleRequestBody(theme: "  ", jlptLevels: [.n4], settings: settings)
        expect(compactBody.messages.last?.content.contains("隨機") == true || compactBody.messages.last?.content.contains("random".lowercased()) == true, "empty theme should fall back to random prompt")

        let draft = try OpenAICompatibleLLMClient.decodeArticle(
            from: #"{"theme":"旅行","title":"京都之旅","text":"今日は京都に行きました。"}"#,
            fallbackTheme: "fallback"
        )
        expect(draft.theme == "旅行", "article theme should decode")
        expect(draft.title == "京都之旅", "article title should decode")
        expect(draft.text == "今日は京都に行きました。", "article text should decode")

        let fallbackDraft = try OpenAICompatibleLLMClient.decodeArticle(
            from: #"{"theme":"","title":"","text":"本文"}"#,
            fallbackTheme: "備用"
        )
        expect(fallbackDraft.theme == "備用", "empty theme should fall back to provided theme")
        expect(fallbackDraft.title == "備用", "empty title should fall back to theme")
    }

    private static func pipelineGeneratesAIArticleAndCards() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        var settings = AppSettings()
        settings.aiArticleLevels = [.n3, .n2]
        settings.aiArticleCustomTheme = "旅行"
        let captured = settings
        try await store.update { state in
            state.settings = captured
        }

        let pipeline = LearningPipeline(
            store: store,
            crawler: MockCrawler(document: CrawledDocument(
                sourceId: UUID(),
                url: URL(string: "https://example.com")!,
                title: "unused",
                plainText: "unused",
                contentHash: "unused"
            )),
            llmClient: MockLLMClient(cardURL: URL(string: "https://example.com")!)
        )

        let article = await pipeline.generateAIArticleNow(theme: "旅行")
        expect(article != nil, "pipeline should return generated article")
        let snapshot = await store.read()
        expect(snapshot.generatedArticles.count == 1, "generated article should be persisted")
        expect(snapshot.documents.count == 1, "AI article should also become a crawled document")
        expect(snapshot.cards.count == 1, "AI article should produce at least one card")
        expect(snapshot.cards[0].word == "電車", "card from AI article should come from mock client")
        expect(snapshot.sources.contains(where: { $0.id == AISource.sentinelSourceId }), "sentinel AI source should be created")
        let sentinel = snapshot.sources.first(where: { $0.id == AISource.sentinelSourceId })
        expect(sentinel?.extractionPrompt.contains("旅行") == true, "sentinel extraction prompt should reflect theme")
        expect(sentinel?.lastError == nil, "sentinel source should have no error")

        let dup = await pipeline.generateAIArticleNow(theme: "旅行")
        expect(dup == nil, "duplicate AI article should be skipped")

        let afterDup = await store.read()
        expect(afterDup.generatedArticles.count == 1, "duplicate should not be stored again")
    }

    private static func storePersistsGeneratedArticles() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        let article = GeneratedArticle(
            theme: "旅行",
            jlptLevels: [.n3, .n2],
            title: "京都之旅",
            plainText: "今日は京都に行きました。",
            contentHash: "hash-xyz",
            sourceId: AISource.sentinelSourceId,
            cardCount: 3
        )
        try await store.update { state in
            state.generatedArticles = [article]
        }

        let reloaded = await AppStore(fileURL: fileURL)
        let snapshot = await reloaded.read()
        expect(snapshot.generatedArticles.count == 1, "generated article should persist in SQLite")
        expect(snapshot.generatedArticles[0].title == "京都之旅", "article title should round trip")
        expect(snapshot.generatedArticles[0].jlptLevels == [.n3, .n2], "article levels should round trip")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fatalError("Check failed: \(message)")
        }
    }

    private static func expectThrows(_ operation: () throws -> Void) {
        do {
            try operation()
            fatalError("Check failed: expected throw")
        } catch {}
    }

    private static func card(_ word: String, status: CardStatus, createdAt: Date, lastShownAt: Date?, url: URL) -> LearningCard {
        LearningCard(
            word: word,
            reading: word,
            partOfSpeech: "名詞",
            meaningZh: word,
            grammarNoteZh: "note",
            jlptLevel: .n4,
            verbFormType: .notVerb,
            exampleJa: "example",
            exampleZh: "例句",
            sourceUrl: url,
            status: status,
            createdAt: createdAt,
            lastShownAt: lastShownAt
        )
    }
}

private struct MockCrawler: Crawling {
    var document: CrawledDocument

    func crawl(source: Source) async throws -> CrawledDocument {
        document
    }
}

private struct MockLLMClient: LLMClient {
    var cardURL: URL
    private let articleText = "今日は京都へ行きました。古い寺を見ました。電車の窓から山が見えました。夜は旅館で温泉に入りました。"

    func generateCards(document: CrawledDocument, sourcePrompt: String, settings: AppSettings) async throws -> [LearningCard] {
        [
            LearningCard(
                word: "電車",
                reading: "でんしゃ",
                partOfSpeech: "名詞",
                meaningZh: "電車",
                grammarNoteZh: "交通工具名詞。",
                jlptLevel: .n4,
                verbFormType: .notVerb,
                exampleJa: "電車に乗ります。",
                exampleZh: "搭電車。",
                sourceUrl: cardURL
            )
        ]
    }

    func generateQuiz(cards: [LearningCard], settings: AppSettings) async throws -> [QuizQuestion] {
        [
            QuizQuestion(
                cardId: cards.first?.id,
                sourceWord: cards.first?.word ?? "電車",
                question: "「電車」の意味は？",
                choices: ["電車", "飛機", "船", "腳踏車"],
                correctAnswer: "電車",
                explanationZh: "電車是鐵路交通工具。"
            )
        ]
    }

    func generateArticle(theme: String, jlptLevels: [JLPTLevel], settings: AppSettings) async throws -> AIArticleDraft {
        let resolvedTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "京都の朝" : theme
        return AIArticleDraft(
            theme: resolvedTheme,
            title: "\(resolvedTheme)の話",
            text: articleText
        )
    }
}
