import Foundation
import JapaneseLearningCardCore

@main
struct CoreChecks {
    static func main() async throws {
        try sourceValidatorAcceptsHTTPAndHTTPS()
        schedulerClampsIntervals()
        cardSelectorPrioritizesFreshThenOldestReviewingAndSkipsSkipped()
        htmlExtractorRemovesScriptsStylesTagsAndDecodesEntities()
        try openAICompatibleRequestAndCardDecoding()
        try exampleReadingDecoding()
        try await pipelineRefreshesEnabledSourcesWithMocks()
        try await storePersistsQuizQuestions()
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
}
