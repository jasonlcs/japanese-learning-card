import Foundation
import JapaneseLearningCardCore

@main
struct CoreChecks {
    static func main() async throws {
        try sourceValidatorAcceptsHTTPAndHTTPS()
        try sourceValidatorBlocksSSRF()
        webCrawlerUsesCustomUserAgent()
        schedulerClampsIntervals()
        schedulerComputesNextAIArticleFireDate()
        cardSelectorPrioritizesFreshThenOldestReviewingAndSkipsSkipped()
        htmlExtractorRemovesScriptsStylesTagsAndDecodesEntities()
        try openAICompatibleRequestAndCardDecoding()
        try manualCardsRequestAndN5Retention()
        try exampleReadingDecoding()
        try await pipelineRefreshesEnabledSourcesWithMocks()
        try await pipelineSkipsAISentinelWhenRefreshingSources()
        try await storePersistsQuizQuestions()
        try await storeMigratesLegacyDatabaseWhenNeeded()
        localDatabaseURLIsScopedByICloudIdentity()
        try await storeReloadsFromDiskWhenDatabaseChangesExternally()
        try await storeUpdateMergesExternalChangesBeforeWriting()
        try await storeUpdatePreservesInterleavedConcurrentWrites()
        try aiArticleRequestAndDecoding()
        try articleDecodingHandlesReasoningModelOutput()
        try structuredOutputIsSentPerProvider()
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

    private static func webCrawlerUsesCustomUserAgent() {
        let userAgent = WebCrawler.userAgent
        expect(userAgent.contains("JapaneseLearningCard"), "WebCrawler should identify with the app's custom User-Agent")
        expect(!userAgent.contains("Mozilla"), "WebCrawler should not spoof a browser User-Agent")
    }

    private static func schedulerClampsIntervals() {
        let policy = SchedulerPolicy()
        let settings = AppSettings(displayIntervalMinutes: 0, visibleDurationSeconds: 1, crawlIntervalHours: 0)

        expect(policy.displayInterval(settings: settings) == 60, "display interval should clamp to 60 seconds")
        expect(policy.visibleDuration(settings: settings) == 3, "visible duration should clamp to 3 seconds")
        expect(policy.crawlInterval(settings: settings) == 3600, "crawl interval should clamp to 1 hour")
    }

    private static func schedulerComputesNextAIArticleFireDate() {
        let policy = SchedulerPolicy()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!

        // 2026-06-24 是星期三 (Calendar weekday 4)。
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 24, hour: 8, minute: 0))!

        // 今天稍晚的時刻、且今天有被選 → 應排在今天。
        let todayLater = AppSettings(aiArticleScheduleHour: 21, aiArticleScheduleMinute: 30, aiArticleWeekdays: [4])
        let fire1 = policy.nextAIArticleFireDate(settings: todayLater, after: now, calendar: calendar)
        expect(fire1 != nil, "should find a fire date when today's weekday is selected and time is later")
        let comps1 = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire1!)
        expect(comps1.day == 24 && comps1.hour == 21 && comps1.minute == 30, "fire date should be today at the scheduled time")

        // 今天較早的時刻已過 → 應跳到下一個被選的星期幾 (週五=6, 即 6/26)。
        let timePassed = AppSettings(aiArticleScheduleHour: 7, aiArticleScheduleMinute: 0, aiArticleWeekdays: [6])
        let fire2 = policy.nextAIArticleFireDate(settings: timePassed, after: now, calendar: calendar)!
        let comps2 = calendar.dateComponents([.day, .hour], from: fire2)
        expect(comps2.day == 26 && comps2.hour == 7, "fire date should roll to the next selected weekday")

        // 沒有任何星期幾 → 不觸發。
        let noDays = AppSettings(aiArticleWeekdays: [])
        expect(policy.nextAIArticleFireDate(settings: noDays, after: now, calendar: calendar) == nil, "no weekdays should yield nil")
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

    private static func manualCardsRequestAndN5Retention() throws {
        let settings = AppSettings(providerConfig: ProviderConfig(baseURL: URL(string: "https://api.example.test/v1")!, model: "custom-model"))
        let body = OpenAICompatibleLLMClient.manualCardsRequestBody(
            text: "りんご、みかん、勉強する",
            instruction: "只挑名詞",
            settings: settings
        )
        expect(body.model == "custom-model", "manual request should use configured model")
        expect(body.messages.last?.content.contains("りんご、みかん、勉強する") == true, "manual request should include pasted text")
        expect(body.messages.last?.content.contains("只挑名詞") == true, "manual request should include user instruction")
        expect(body.messages.first?.content.contains("包含 N5") == true || body.messages.first?.content.contains("N5") == true, "manual prompt should mention keeping all levels")

        let json = """
        {"cards":[{"word":"水","reading":"みず","partOfSpeech":"名詞","meaningZh":"水","grammarNoteZh":"基本名詞。","jlptLevel":"N5","verbFormType":"非動詞","exampleJa":"水を飲みます。","exampleReading":"みずをのみます。","exampleZh":"喝水。"}]}
        """
        let url = URL(string: "manual-input://test")!
        let dropped = try OpenAICompatibleLLMClient.decodeCards(from: json, sourceURL: url)
        expect(dropped.isEmpty, "default decode should still drop N5")
        let kept = try OpenAICompatibleLLMClient.decodeCards(from: json, sourceURL: url, includeN5: true)
        expect(kept.count == 1 && kept[0].jlptLevel == .n5, "manual decode should retain N5 cards")
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

    private static func pipelineSkipsAISentinelWhenRefreshingSources() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.json")
        let store = await AppStore(fileURL: fileURL)
        let sentinel = Source(
            id: AISource.sentinelSourceId,
            url: AISource.sentinelURL,
            isEnabled: true,
            extractionPrompt: AISource.sentinelExtractionPrompt
        )
        try await store.update { state in
            state.sources = [sentinel]
        }

        let pipeline = LearningPipeline(
            store: store,
            crawler: FailingCrawler(),
            llmClient: MockLLMClient(cardURL: AISource.sentinelURL)
        )

        await pipeline.refreshEnabledSources()
        let snapshot = await store.read()

        expect(snapshot.documents.isEmpty, "AI sentinel should not be crawled as a web source")
        expect(snapshot.cards.isEmpty, "AI sentinel should not generate cards during source refresh")
        expect(snapshot.sources[0].lastError == nil, "AI sentinel should not receive a crawler error during source refresh")
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

    private static func localDatabaseURLIsScopedByICloudIdentity() {
        let base = URL(fileURLWithPath: "/tmp/base")

        // 未登入 iCloud：沿用原本的 store.sqlite，不影響既有資料。
        let anonymous = AppStore.makeLocalDatabaseURL(base: base, identitySuffix: nil)
        expect(anonymous.lastPathComponent == "store.sqlite", "no iCloud identity should use the legacy store.sqlite path")

        // 不同 iCloud 身分 → 不同檔，互不共用。
        let userA = AppStore.makeLocalDatabaseURL(base: base, identitySuffix: "aaaa1111")
        let userB = AppStore.makeLocalDatabaseURL(base: base, identitySuffix: "bbbb2222")
        expect(userA.lastPathComponent == "store-aaaa1111.sqlite", "identity A should get its own local file")
        expect(userA != userB, "different iCloud identities must not share the same local database file")
        expect(userA != anonymous, "an identity-scoped file must differ from the anonymous one")
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

    private static func storeUpdateMergesExternalChangesBeforeWriting() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")

        // Computer A and Computer B both open the same database (simulating iCloud Drive).
        let storeA = await AppStore(fileURL: fileURL)
        let storeB = await AppStore(fileURL: fileURL)

        // Computer B adds a source while Computer A still holds a stale snapshot.
        let source = Source(url: URL(string: "https://example.com/article")!)
        try await storeB.update { state in
            state.sources = [source]
        }

        // Computer A now performs its own update (e.g., changes a setting).
        // Without the fix, A would overwrite B's source with its stale empty list.
        // With the fix, A first reloads B's changes and then applies its mutation on top.
        try await storeA.update { state in
            state.settings.displayIntervalMinutes = 42
        }

        let snapshot = await storeA.read()
        expect(snapshot.settings.displayIntervalMinutes == 42, "computer A's setting change should be preserved")
        expect(snapshot.sources.count == 1, "computer B's source should not be overwritten by computer A's update")
        expect(snapshot.sources.first?.url == source.url, "computer B's source URL should survive computer A's update")
    }

    private static func storeUpdatePreservesInterleavedConcurrentWrites() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")

        // Two connections to the same file (e.g., two Macs via iCloud Drive).
        let storeA = await AppStore(fileURL: fileURL)
        let storeB = await AppStore(fileURL: fileURL)
        let url = URL(string: "https://example.com")!

        // Alternate appends; each writer's snapshot is stale by the other's last commit.
        // Optimistic concurrency must merge rather than overwrite, losing nothing.
        for i in 0..<5 {
            try await storeA.update { $0.cards.append(card("A\(i)", status: .new, createdAt: Date(), lastShownAt: nil, url: url)) }
            try await storeB.update { $0.cards.append(card("B\(i)", status: .new, createdAt: Date(), lastShownAt: nil, url: url)) }
        }

        let snapshot = await storeB.read()
        expect(snapshot.cards.count == 10, "all interleaved appends from both writers must be preserved")
        for i in 0..<5 {
            expect(snapshot.cards.contains(where: { $0.word == "A\(i)" }), "writer A's card A\(i) must survive")
            expect(snapshot.cards.contains(where: { $0.word == "B\(i)" }), "writer B's card B\(i) must survive")
        }
    }

    private static func storeReloadsFromDiskWhenDatabaseChangesExternally() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        try await store.update { state in
            state.settings.displayIntervalMinutes = 5
        }

        // A second connection (e.g., another Mac via iCloud Drive) commits a change.
        let externalStore = await AppStore(fileURL: fileURL)
        try await externalStore.update { state in
            state.settings.displayIntervalMinutes = 17
        }

        // The first store should detect the external commit via SQLite's data_version
        // cookie and reload — even when both writes share the same filesystem mtime.
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

    private static func articleDecodingHandlesReasoningModelOutput() throws {
        // 推理型模型在真正的 JSON 前輸出 <think>…</think>，且思考內含草稿大括號。
        let content = """
        <think>
        Let me draft the JSON:
        {
          "theme": "草稿",
          "title": "これは草稿です",
          "text": "本文の下書き…"
        }
        Hmm, let me reconsider the grammar { not balanced here } and finalize.
        </think>
        {"theme":"推し活","title":"私の推し活","text":"私は毎週末ライブに行きます。"}
        """

        let draft = try OpenAICompatibleLLMClient.decodeArticle(from: content, fallbackTheme: "fallback")
        expect(draft.theme == "推し活", "should decode the real JSON after </think>, not the draft inside it")
        expect(draft.title == "私の推し活", "title should come from the final answer")
        expect(draft.text == "私は毎週末ライブに行きます。", "text should come from the final answer")

        // 也要相容包在 markdown code fence 內、且有前後說明文字的情況。
        let fenced = """
        Here is the article:
        ```json
        {"theme":"旅行","title":"京都の旅","text":"今日は京都に行きました。"}
        ```
        Hope this helps!
        """
        let fencedDraft = try OpenAICompatibleLLMClient.decodeArticle(from: fenced, fallbackTheme: "fallback")
        expect(fencedDraft.theme == "旅行", "should decode JSON wrapped in markdown fence with surrounding prose")
        expect(fencedDraft.text == "今日は京都に行きました。", "fenced article text should decode")

        // 推理標記是泛化處理的，不限 <think>；換成 <reasoning> 也要能運作。
        let reasoning = """
        <reasoning>draft {"x":1} more</reasoning>
        {"theme":"料理","title":"和食","text":"味噌汁を作ります。"}
        """
        let reasoningDraft = try OpenAICompatibleLLMClient.decodeArticle(from: reasoning, fallbackTheme: "fallback")
        expect(reasoningDraft.theme == "料理", "should handle generic reasoning markers, not only <think>")
        expect(reasoningDraft.text == "味噌汁を作ります。", "text after </reasoning> should decode")
    }

    private static func structuredOutputIsSentPerProvider() throws {
        let encoder = JSONEncoder()

        // OpenAI preset 預設要求結構化輸出。
        let openAISettings = AppSettings(providerConfig: ProviderConfig(preset: .openAI))
        expect(openAISettings.providerConfig.structuredOutput == .jsonObject, "OpenAI preset should default to json_object")
        let openAIBody = OpenAICompatibleLLMClient.articleRequestBody(theme: "旅行", jlptLevels: [.n2], settings: openAISettings)
        let openAIJSON = String(decoding: try encoder.encode(openAIBody), as: UTF8.self)
        expect(openAIJSON.contains("response_format"), "OpenAI request should include response_format")
        expect(openAIJSON.contains("json_object"), "OpenAI request should request json_object")

        // 第三方/本地 preset 預設不送 response_format，避免不支援的 endpoint 回 400。
        let zenSettings = AppSettings(providerConfig: ProviderConfig(preset: .openCodeZen, structuredOutput: .off))
        expect(zenSettings.providerConfig.structuredOutput == .off, "non-OpenAI preset should be able to disable structured output")
        let zenBody = OpenAICompatibleLLMClient.articleRequestBody(theme: "旅行", jlptLevels: [.n2], settings: zenSettings)
        let zenJSON = String(decoding: try encoder.encode(zenBody), as: UTF8.self)
        expect(!zenJSON.contains("response_format"), "request should omit response_format when structured output is off")
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
        expect(article.generatedArticle != nil, "pipeline should return generated article")
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
        expect(dup.generatedArticle == nil, "duplicate AI article should be skipped")

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

private struct FailingCrawler: Crawling {
    func crawl(source: Source) async throws -> CrawledDocument {
        throw NSError(domain: "FailingCrawler", code: 1)
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
