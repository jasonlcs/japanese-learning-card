import Foundation
import os
import JapaneseLearningCardCore

@main
struct CoreChecks {
    static func main() async throws {
        try sourceValidatorAcceptsHTTPAndHTTPS()
        try sourceValidatorBlocksSSRF()
        webCrawlerUsesCustomUserAgent()
        try await sourceConnectionTesterRejectsInvalidScheme()
        try await sourceConnectionTesterClassifiesSuccess()
        try await sourceConnectionTesterDetectsNeedsBrowser()
        try await sourceConnectionTesterDetectsBlockedByUserAgent()
        try await sourceConnectionTesterClassifiesTimeout()
        sourceDiagnosticReportsAIParseResult()
        schedulerClampsIntervals()
        schedulerComputesNextAIArticleFireDate()
        cardSelectorRandomlyChoosesReviewableCardsOnly()
        htmlExtractorRemovesScriptsStylesTagsAndDecodesEntities()
        try openAICompatibleRequestAndCardDecoding()
        try quizDecodingDistributesCorrectAnswerPositions()
        try manualCardsRequestAndN5Retention()
        try cardDecodingSalvagesMalformedAndTruncatedOutput()
        try exampleReadingDecoding()
        try await pipelineRefreshesEnabledSourcesWithMocks()
        try await pipelineSkipsAISentinelWhenRefreshingSources()
        try await pipelineBackfillsIncompleteCardsFromStoredDocuments()
        try await storePersistsQuizQuestions()
        try await storageFactorySelectsDatabaseURLByMode()
        try await sqliteUserDataStoreRoundTripsSnapshotInFolder()
        try await storeMigratesLegacyDatabaseWhenNeeded()
        try storeMigratesIdentityScopedStoreToCanonicalStore()
        try await storeReloadsFromDiskWhenDatabaseChangesExternally()
        try await storeForceReloadPicksUpAtomicFileReplace()
        try await storeUpdateMergesExternalChangesBeforeWriting()
        try await storeUpdatePreservesInterleavedConcurrentWrites()
        try aiArticleRequestAndDecoding()
        try articleDecodingHandlesReasoningModelOutput()
        try structuredOutputIsSentPerProvider()
        try googleAIStudioPresetTargetsGeminiOpenAIEndpoint()
        ollamaPresetSupportsLocalKeylessProvider()
        try rubyRequestStreamsAndSSELinesAssemble()
        try essayOutputStripsEmphasisMarkers()
        vocabularyHighlightMatchesWordsAndSegments()
        rubyRepairFixesDroppedPunctuationButNotContentMismatch()
        try await pipelineGeneratesAIArticleAndCards()
        try await pipelineParseAndStoreForValidationRegistersSourceAndCards()
        try await storePersistsGeneratedArticles()
        try generatedArticleKindDecodingBackfillsLegacyData()
        try syncedBaseStoreRoundTrips()
        try mergerKeepsLocalOnlyChanges()
        try mergerKeepsRemoteOnlyChanges()
        try mergerTakesRemoteWhenLocalEqualsBase()
        try mergerTakesLocalWhenRemoteEqualsBase()
        try mergerDetectsConflictAndResolvesByLWW()
        try mergerTreatsCardShallowDiffAsNonConflict()
        try mergerDetectsSettingsConflict()
        try mergerHandlesNilBase()
        try await appStoreStampsUpdatedAtOnChangedRecords()
        try await cloudKitTransportSubmitsFirstTimeWithoutRetry()
        try await cloudKitTransportRetriesOnceOnConflict()
        try await cloudKitTransportFetchReturnsNilWhenEmpty()
        try await cloudKitTransportFetchDecodesPayload()
        try await appStoreAppliesMergedSnapshot()
        try await syncCoordinatorPushesLocalToCloud()
        try await syncCoordinatorSkipsPushWhenLocalEmpty()
        try await syncCoordinatorPullsAndMergesRemoteChanges()
        try await syncCoordinatorMergesConflictingChanges()
        try await appStoreAutoDetectsDeletedSource()
        try await appStoreUndeleteRemovesFromDeletedSet()
        try mergerAppliesDeletionsToAllTables()
        try await syncCoordinatorPropagatesDeletionToOtherMac()
        try mergerConflictRecordContainsLocalRemoteBaseJSON()
        try await conflictStorePersistsAndReloads()
        try await aiRequestLogStoreMirrorsLatestFlow()
        print("All JapaneseLearningCardCore checks passed.")
    }

    private static func aiRequestLogStoreMirrorsLatestFlow() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-log-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AIRequestLogStore(directory: dir)

        await AITraceContext.$traceId.withValue("trace-A") {
            await AITraceContext.$flow.withValue("generateAIArticleNow") {
                await store.appendEvent("flow.start", operation: "generateAIArticleNow")
                await store.appendEvent("flow.completed", operation: "generateAIArticleNow", startedAt: Date(timeIntervalSinceNow: -1.5))
            }
        }
        await AITraceContext.$traceId.withValue("trace-B") {
            await AITraceContext.$flow.withValue("generateQuiz") {
                await store.appendEvent("flow.start", operation: "generateQuiz")
                await store.appendEvent("flow.completed", operation: "generateQuiz", startedAt: Date())
            }
        }
        // 已結束（或並行中）舊流程的尾段事件不應重置或混入 ai-latest.log。
        await AITraceContext.$traceId.withValue("trace-A") {
            await store.appendEvent("llm.response", operation: "generateArticle")
        }

        let fullLines = try String(contentsOf: store.logFileURL, encoding: .utf8)
            .split(separator: "\n")
        expect(fullLines.count == 5, "主 log 應包含全部 5 筆事件")

        let latestLines = try String(contentsOf: store.latestLogFileURL, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        expect(latestLines.count == 2, "ai-latest.log 應只保留最新流程的 2 筆事件")
        expect(latestLines.allSatisfy { $0.contains("trace-B") }, "ai-latest.log 應只包含最新流程的 traceId")
        expect(latestLines.last?.contains("\"startedAt\"") == true, "flow.completed 應記錄 startedAt 起始時間")
        expect(latestLines.last?.contains("\"finishedAt\"") == true, "flow.completed 應記錄 finishedAt 結束時間")
        expect(latestLines.last?.contains("\"durationMilliseconds\"") == true, "flow.completed 應自動計算 duration")
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

    private static func makeTester() -> SourceConnectionTester {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return SourceConnectionTester(session: session, minimumUsefulCharacters: 200)
    }

    private static func sourceConnectionTesterRejectsInvalidScheme() async throws {
        // 不應觸發任何網路請求即判定為 invalidURL。
        MockURLProtocol.handler = { _ in throw URLError(.badServerResponse) }
        defer { MockURLProtocol.handler = nil }
        let diagnostic = await makeTester().test(url: URL(string: "ftp://example.com/file")!)
        expect(diagnostic.outcome == .invalidURL, "ftp scheme should be classified as invalidURL")
        expect(!diagnostic.isReachable, "invalidURL should not be reachable")
    }

    private static func sourceConnectionTesterClassifiesSuccess() async throws {
        let html = "<html><body><p>" + String(repeating: "日本語の勉強。", count: 80) + "</p></body></html>"
        MockURLProtocol.handler = { _ in (200, Data(html.utf8), "text/html") }
        defer { MockURLProtocol.handler = nil }
        let diagnostic = await makeTester().test(url: URL(string: "https://example.com/article")!)
        expect(diagnostic.outcome == .ok, "ample HTML content should classify as ok, got \(diagnostic.outcome)")
        expect(diagnostic.isReachable, "ok should be reachable")
        expect(diagnostic.errorMessageForSource == nil, "reachable source should clear lastError")
    }

    private static func sourceConnectionTesterDetectsNeedsBrowser() async throws {
        let html = "<html><body><p>少し</p></body></html>"
        MockURLProtocol.handler = { _ in (200, Data(html.utf8), "text/html") }
        defer { MockURLProtocol.handler = nil }
        let diagnostic = await makeTester().test(url: URL(string: "https://spa.example.com/")!)
        expect(diagnostic.outcome == .needsBrowser, "tiny body should classify as needsBrowser, got \(diagnostic.outcome)")
        expect(diagnostic.isReachable, "needsBrowser should still count as reachable")
    }

    private static func sourceConnectionTesterDetectsBlockedByUserAgent() async throws {
        // App UA 被擋 (403)，瀏覽器 UA 可通 (200) → 判定為站方針對 UA 阻擋。
        MockURLProtocol.handler = { request in
            let ua = request.value(forHTTPHeaderField: "User-Agent") ?? ""
            if ua.contains("Mozilla") {
                return (200, Data("<html><body>ok</body></html>".utf8), "text/html")
            }
            return (403, Data("forbidden".utf8), "text/plain")
        }
        defer { MockURLProtocol.handler = nil }
        let diagnostic = await makeTester().test(url: URL(string: "https://news.example.com/")!)
        expect(diagnostic.outcome == .blocked, "403 for app UA but 200 for browser UA should classify as blocked, got \(diagnostic.outcome)")
        expect(diagnostic.httpStatus == 403, "blocked diagnostic should report the app UA status")
        expect(diagnostic.errorMessageForSource != nil, "blocked source should set lastError")
    }

    private static func sourceConnectionTesterClassifiesTimeout() async throws {
        MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
        defer { MockURLProtocol.handler = nil }
        let diagnostic = await makeTester().test(url: URL(string: "https://slow.example.com/")!)
        expect(diagnostic.outcome == .timeout, "URLError.timedOut should classify as timeout, got \(diagnostic.outcome)")
        expect(!diagnostic.isReachable, "timeout should not be reachable")
    }

    private static func sourceDiagnosticReportsAIParseResult() {
        let base = SourceDiagnostic(outcome: .ok, summary: "連線正常。")

        // 未跑 AI 測試：不顯示 AI 行，可用來源不應有 lastError。
        expect(base.aiParseSummary == nil, "no AI test should produce no AI summary")
        expect(base.errorMessageForSource == nil, "reachable source without AI error should clear lastError")

        // 解析出卡片：回報張數並加入資料庫、不視為錯誤。
        var ok = base
        ok.aiParsedCardCount = 5
        expect(ok.aiParseSummary == "AI 成功解析出 5 張卡片並加入資料庫。", "should report parsed card count")
        expect(ok.errorMessageForSource == nil, "successful AI parse should not set lastError")

        // 內容重複：回報未重複建立、不算錯誤、不寫回 lastError。
        var duplicate = base
        duplicate.aiParseDuplicate = true
        expect(duplicate.aiParseSummary == "內容與既有資料相同，未重複建立卡片。", "duplicate content should be reported")
        expect(duplicate.errorMessageForSource == nil, "duplicate content is not an error")

        // 解析出 0 張：仍只回報、不設門檻判失敗，但也不算錯誤。
        var zero = base
        zero.aiParsedCardCount = 0
        expect(zero.aiParseSummary == "AI 這次沒解析出任何卡片。", "zero cards should be reported, not thresholded")
        expect(zero.errorMessageForSource == nil, "zero parsed cards is not treated as an error")

        // AI 解析出錯：連得到但實際不可用，錯誤訊息寫回來源。
        var failed = base
        failed.aiParseError = "無法解析模型回應。"
        expect(failed.aiParseSummary == "AI 解析失敗：無法解析模型回應。", "AI error should surface in summary")
        expect(failed.errorMessageForSource == "AI 解析失敗：無法解析模型回應。", "AI parse error should be written back to source")
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

    private static func cardSelectorRandomlyChoosesReviewableCardsOnly() {
        let selector = CardSelector()
        let url = URL(string: "https://example.com")!
        let old = Date(timeIntervalSince1970: 100)
        let recent = Date(timeIntervalSince1970: 200)
        let skipped = card("飛ばす", status: .skipped, createdAt: old, lastShownAt: nil, url: url)
        let reviewingRecent = card("最近", status: .reviewing, createdAt: old, lastShownAt: recent, url: url)
        let fresh = card("新しい", status: .new, createdAt: recent, lastShownAt: nil, url: url)
        let reviewingOld = card("古い", status: .reviewing, createdAt: old, lastShownAt: old, url: url)

        let candidates = [skipped, reviewingRecent, fresh, reviewingOld]
        for _ in 0..<20 {
            let selected = selector.nextCard(from: candidates)
            expect(selected != nil, "reviewable cards should be selected")
            expect(selected?.status != .skipped, "skipped cards should not be selected")
            expect(selected?.status != .learned, "learned cards should not be selected")
        }

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

    private static func quizDecodingDistributesCorrectAnswerPositions() throws {
        let sourceURL = URL(string: "https://example.com")!
        let cards = [card("駅", status: .new, createdAt: Date(), lastShownAt: nil, url: sourceURL)]
        let quizzes = try OpenAICompatibleLLMClient.decodeQuiz(from: """
        {"quizzes":[
          {"sourceWord":"駅","question":"q1","choices":["正解1","誤1","誤2","誤3"],"correctAnswer":"正解1","explanationZh":"解析"},
          {"sourceWord":"駅","question":"q2","choices":["正解2","誤1","誤2","誤3"],"correctAnswer":"正解2","explanationZh":"解析"},
          {"sourceWord":"駅","question":"q3","choices":["正解3","誤1","誤2","誤3"],"correctAnswer":"正解3","explanationZh":"解析"},
          {"sourceWord":"駅","question":"q4","choices":["正解4","誤1","誤2","誤3"],"correctAnswer":"正解4","explanationZh":"解析"},
          {"sourceWord":"駅","question":"q5","choices":["正解5","誤1","誤2","誤3"],"correctAnswer":"正解5","explanationZh":"解析"},
          {"sourceWord":"駅","question":"q6","choices":["正解6","誤1","誤2","誤3"],"correctAnswer":"正解6","explanationZh":"解析"}
        ]}
        """, cards: cards)

        let answerIndexes = quizzes.compactMap { $0.choices.firstIndex(of: $0.correctAnswer) }
        expect(quizzes.count == 6, "all valid quizzes should decode")
        expect(Set(answerIndexes).count > 1, "decoder should distribute correct answers across option positions")
        expect(!answerIndexes.allSatisfy { $0 == 0 }, "correct answers should not all remain in the first option")
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

    private static func cardDecodingSalvagesMalformedAndTruncatedOutput() throws {
        let url = URL(string: "https://www.yomiuri.co.jp/news/")!

        // 1) 必填欄位回成 null：整批不應失敗，該卡以空字串補上。
        let withNull = """
        {"cards":[{"word":"報道","reading":"ほうどう","partOfSpeech":"名詞","meaningZh":"報導","grammarNoteZh":null,"jlptLevel":"N2","verbFormType":"非動詞","exampleJa":"報道がある。","exampleZh":"有報導。"}]}
        """
        let nullCards = try OpenAICompatibleLLMClient.decodeCards(from: withNull, sourceURL: url, includeN5: true)
        expect(nullCards.count == 1, "null field should not fail the whole batch")
        expect(nullCards[0].word == "報道" && nullCards[0].grammarNoteZh == "", "null field should fall back to empty string")

        // 2) 輸出被截斷(最後一張不完整)：完整的那些仍應救回，不完整的略過。
        let truncated = """
        {"cards":[{"word":"記者","reading":"きしゃ","partOfSpeech":"名詞","meaningZh":"記者","grammarNoteZh":"職業名詞。","jlptLevel":"N2","verbFormType":"非動詞","exampleJa":"記者が来た。","exampleReading":"きしゃがきた。","exampleZh":"記者來了。"},{"word":"取材","reading":"しゅざ
        """
        let salvaged = try OpenAICompatibleLLMClient.decodeCards(from: truncated, sourceURL: url, includeN5: true)
        expect(salvaged.count == 1, "complete cards should survive a truncated trailing object")
        expect(salvaged[0].word == "記者", "salvaged card content should be intact")

        // 3) 中間夾一張格式錯誤的卡(choices 型別不符)：壞的跳過，前後好的保留。
        let mixed = """
        {"cards":[
          {"word":"政府","reading":"せいふ","partOfSpeech":"名詞","meaningZh":"政府","grammarNoteZh":"機構名詞。","jlptLevel":"N3","verbFormType":"非動詞","exampleJa":"政府が発表した。","exampleReading":"せいふがはっぴょうした。","exampleZh":"政府發表了。"},
          {"word":12345},
          {"word":"発表","reading":"はっぴょう","partOfSpeech":"名詞","meaningZh":"發表","grammarNoteZh":"する動詞語幹。","jlptLevel":"N3","verbFormType":"する動詞","exampleJa":"結果を発表する。","exampleReading":"けっかをはっぴょうする。","exampleZh":"發表結果。"}
        ]}
        """
        let mixedCards = try OpenAICompatibleLLMClient.decodeCards(from: mixed, sourceURL: url, includeN5: true)
        expect(mixedCards.count == 2, "malformed card in the middle should be skipped, others kept")
        expect(mixedCards.map(\.word) == ["政府", "発表"], "good cards around a bad one should be preserved in order")
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

    private static func pipelineBackfillsIncompleteCardsFromStoredDocuments() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        let source = Source(url: URL(string: "https://example.com/article")!)
        let document = CrawledDocument(
            sourceId: source.id,
            url: source.url,
            title: "Stored",
            plainText: "電車に乗ります。",
            contentHash: "stored-doc"
        )
        let oldId = UUID()
        let oldLastShownAt = Date(timeIntervalSince1970: 123)
        let oldCard = LearningCard(
            id: oldId,
            word: "電車",
            reading: "",
            partOfSpeech: "",
            meaningZh: "old",
            grammarNoteZh: "",
            jlptLevel: .unknown,
            verbFormType: .unknown,
            exampleJa: "古い例",
            exampleReading: "",
            exampleZh: "",
            sourceUrl: source.url,
            status: .reviewing,
            createdAt: Date(timeIntervalSince1970: 10),
            lastShownAt: oldLastShownAt,
            shownCount: 7
        )
        try await store.update { state in
            state.sources = [source]
            state.documents = [document]
            state.cards = [oldCard]
        }

        let pipeline = LearningPipeline(
            store: store,
            crawler: FailingCrawler(),
            llmClient: MockLLMClient(cardURL: source.url)
        )

        let outcome = await pipeline.backfillExistingCards()
        let snapshot = await store.read()
        let card = snapshot.cards[0]

        expect(outcome.updatedCards == 1, "backfill should update one incomplete card")
        expect(snapshot.cards.count == 1, "backfill should not duplicate existing cards")
        expect(card.id == oldId, "backfill should preserve existing card identity")
        expect(card.status == .reviewing, "backfill should preserve review status")
        expect(card.lastShownAt == oldLastShownAt, "backfill should preserve review timestamp")
        expect(card.shownCount == 7, "backfill should preserve shown count")
        expect(card.grammarNoteZh == "交通工具名詞。", "backfill should copy regenerated grammar note")
        expect(card.exampleReading == "でんしゃにのります。", "backfill should copy regenerated example reading")
        expect(card.jlptLevel == .n4, "backfill should copy regenerated JLPT level")
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

    private static func storageFactorySelectsDatabaseURLByMode() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = StorageSettings(mode: .localOnly, localDataPath: tempDirectory.appendingPathComponent("local").path)
        let drive = StorageSettings(mode: .iCloudDriveFolder, iCloudDriveFolderPath: tempDirectory.appendingPathComponent("drive").path)
        let cloud = StorageSettings(mode: .cloudKit)

        expect(UserDataStoreFactory.databaseURL(for: local).path.hasSuffix("/local/store.sqlite"), "local mode should use local folder")
        expect(UserDataStoreFactory.databaseURL(for: drive).path.hasSuffix("/drive/store.sqlite"), "iCloud Drive mode should use selected folder")
        expect(UserDataStoreFactory.databaseURL(for: cloud) == AppStore.localDatabaseURL(), "CloudKit mode should keep existing local backing store")
    }

    private static func sqliteUserDataStoreRoundTripsSnapshotInFolder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = StorageSettings(mode: .iCloudDriveFolder, iCloudDriveFolderPath: folder.path)
        let dataStore = await UserDataStoreFactory.create(settings: settings)
        let source = makeSource(url: "https://folder.example.com")
        try await dataStore.saveSnapshot(makeSnapshot(sources: [source]))

        let reloaded = await UserDataStoreFactory.create(settings: settings)
        let snapshot = try await reloaded.loadSnapshot()
        let health = try await reloaded.getHealth()

        expect(snapshot.sources.count == 1, "folder data store should persist snapshot")
        expect(snapshot.sources[0].url.absoluteString == "https://folder.example.com", "folder data store should round trip source")
        expect(health.isWritable, "folder data store should report writable health")
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

    /// 舊版「依 iCloud 身分雜湊分檔」(store-<hash>.sqlite) 要能遷移到統一的
    /// store.sqlite：挑檔案最大(資料最完整)的一份，且忽略 synced base。
    private static func storeMigratesIdentityScopedStoreToCanonicalStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("a".utf8).write(to: dir.appendingPathComponent("store-aaaa1111.sqlite"))
        try Data("bbbbbbbb".utf8).write(to: dir.appendingPathComponent("store-bbbb2222.sqlite"))
        // synced base 雖然最大也必須被忽略, 不能拿它當主 DB。
        try Data("synced-base-should-be-ignored".utf8).write(to: dir.appendingPathComponent("store-synced.sqlite"))

        let canonical = dir.appendingPathComponent("store.sqlite")
        try AppStore.migrateIdentityScopedStoreIfNeeded(to: canonical)

        expect(FileManager.default.fileExists(atPath: canonical.path), "canonical store.sqlite should be created from a scoped file")
        let migrated = try Data(contentsOf: canonical)
        expect(String(decoding: migrated, as: UTF8.self) == "bbbbbbbb", "should migrate the largest non-synced scoped store")

        // 冪等: 再跑一次不應覆蓋已存在的 store.sqlite。
        try AppStore.migrateIdentityScopedStoreIfNeeded(to: canonical)
        let again = try Data(contentsOf: canonical)
        expect(String(decoding: again, as: UTF8.self) == "bbbbbbbb", "re-running migration must be idempotent")
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

    /// 模擬 iCloud Drive 用 atomic replace 換檔後，AppStore 必須能靠
    /// `forceReloadFromDisk` 撈到新檔的內容。
    private static func storeForceReloadPicksUpAtomicFileReplace() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("store.sqlite")

        let store = await AppStore(fileURL: fileURL)
        try await store.update { state in
            state.settings.displayIntervalMinutes = 5
        }

        // 另一台 Mac 寫了一份新 SQLite，再用 atomic replace 蓋過原檔。
        // 這是 iCloud Drive 同步的典型行為：路徑一樣，inode 換掉，
        // 原本的 SQLite handle 仍掛在舊 inode 上，看不到 data_version 變化。
        let incomingURL = dir.appendingPathComponent("store-incoming.sqlite")
        let externalStore = await AppStore(fileURL: incomingURL)
        try await externalStore.update { state in
            state.settings.displayIntervalMinutes = 42
        }

        _ = try FileManager.default.replaceItemAt(
            fileURL,
            withItemAt: incomingURL,
            backupItemName: nil,
            options: []
        )

        // 一般 `read()` 在這個情境下不會看到新內容(舊 inode 沒變)，
        // 由 `DatabaseFilePresenter` 觸發的 `forceReloadFromDisk` 才是正確路徑。
        try await store.forceReloadFromDisk()
        let snapshot = await store.read()
        expect(snapshot.settings.displayIntervalMinutes == 42, "force reload must pick up the content of the atomically replaced file")
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

    private static func googleAIStudioPresetTargetsGeminiOpenAIEndpoint() throws {
        let preset = ProviderPreset.googleAIStudio
        expect(preset.defaultBaseURL.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai",
               "Google AI Studio preset should target the Gemini OpenAI-compatible endpoint")
        expect(preset.defaultModel == "gemini-3.5-flash", "default model should be Gemini 3.5 Flash")
        expect(preset.defaultFastModel == "gemini-3.1-flash-lite", "default fast model should be Gemini 3.1 Flash-Lite")
        expect(preset.defaultStructuredOutput == .off, "Gemini preset should default response_format off")
        expect(!preset.usesCuratedModelList, "Google AI Studio should offer full model list")
        expect(preset.fallbackModels == ["gemini-3.5-flash", "gemini-3.1-flash-lite", "gemma-4-26b-a4b-it", "gemma-4-31b-it"],
               "Google AI Studio fallback models should include Gemini and Gemma models")

        // 以選擇 preset 後的設定組請求，應帶 Gemini 模型、不帶 response_format。
        let settings = AppSettings(providerConfig: ProviderConfig(
            preset: .googleAIStudio,
            baseURL: preset.defaultBaseURL,
            model: preset.defaultModel,
            fastModel: preset.defaultFastModel,
            structuredOutput: preset.defaultStructuredOutput
        ))
        let body = OpenAICompatibleLLMClient.articleRequestBody(theme: "旅行", jlptLevels: [.n2], settings: settings)
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        expect(body.model == "gemini-3.5-flash", "request should use the Gemini 3.5 Flash model")
        expect(!json.contains("response_format"), "Gemini request should omit response_format by default")
    }

    private static func rubyRequestStreamsAndSSELinesAssemble() throws {
        // 注音與短文請求必須開串流，避開 gateway 對非串流長請求的時間預算。
        let settings = AppSettings(providerConfig: ProviderConfig(preset: .openCodeGo, structuredOutput: .off))
        let body = OpenAICompatibleLLMClient.rubyForTextsRequestBody(texts: ["日本語"], settings: settings)
        expect(body.stream == true, "ruby request should enable SSE streaming")
        let json = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        expect(json.contains("\"stream\":true"), "encoded ruby request should carry stream:true")
        let essayBody = OpenAICompatibleLLMClient.essayRequestBody(theme: "旅行", vocabularyWords: ["旅"], settings: settings)
        expect(essayBody.stream == true, "essay request should enable SSE streaming")

        // 其他請求未指定 stream 時不得送出該欄位。
        let quizBody = OpenAICompatibleLLMClient.quizRequestBody(cards: [], settings: settings)
        let quizJSON = String(decoding: try JSONEncoder().encode(quizBody), as: UTF8.self)
        expect(!quizJSON.contains("\"stream\""), "non-streaming requests should omit the stream field")

        // SSE 行解析：組 delta.content、忽略 reasoning 增量 / [DONE] / 非 data 行。
        let lines = [
            ": keep-alive comment",
            "data: {\"choices\":[{\"delta\":{\"content\":\"{\\\"results\\\":\"}}]}",
            "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"thinking...\"}}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"[]}\"}}]}",
            "data: [DONE]"
        ]
        let content = lines.compactMap(OpenAICompatibleLLMClient.streamedContentDelta(fromSSELine:)).joined()
        expect(content == "{\"results\":[]}", "SSE deltas should assemble into the full content, got: \(content)")
    }

    private static func essayOutputStripsEmphasisMarkers() throws {
        // App 不渲染 Markdown：模型輸出的 **強調** 必須在解碼時剝除。
        let content = """
        {"isValidPrompt":true,"validationError":"","title":"**放送**の一日","paragraphs":[{"japanese":"この**放送**は面白いです。","translation":"這個**廣播**很有趣。"}]}
        """
        let payload = try OpenAICompatibleLLMClient.decodeEssay(from: content)
        expect(payload.title == "放送の一日", "decodeEssay should strip ** from the title")
        expect(payload.paragraphs.first?.japanese == "この放送は面白いです。", "decodeEssay should strip ** from japanese text")
        expect(payload.paragraphs.first?.translation == "這個廣播很有趣。", "decodeEssay should strip ** from translation")

        // 既有 DB 資料殘留 ** 時，顯示／注音／匯出共用的 resolvedParagraphs 也要剝除。
        let stored = GeneratedArticle(
            kind: .essay,
            theme: "測試",
            jlptLevels: [.n3],
            title: "放送の一日",
            plainText: "この**放送**は面白いです。",
            contentHash: "hash",
            sourceId: UUID(),
            paragraphs: [ArticleParagraph(japanese: "この**放送**は面白いです。", translation: "這個**廣播**很有趣。")]
        )
        expect(stored.resolvedParagraphs.first?.japanese == "この放送は面白いです。",
               "resolvedParagraphs should strip ** left in stored data")
        expect(stored.resolvedParagraphs.first?.translation == "這個廣播很有趣。",
               "resolvedParagraphs should strip ** from stored translation")
    }

    private static func vocabularyHighlightMatchesWordsAndSegments() {
        // 純文字：找出單字出現的字元區間，重複出現要全標。
        let text = "この放送は面白い。放送を聞く。"
        let ranges = RubySupport.highlightRanges(in: text, words: ["放送"])
        expect(ranges == [2..<4, 9..<11], "highlightRanges should mark every occurrence, got: \(ranges)")
        expect(RubySupport.highlightRanges(in: text, words: []).isEmpty, "no words means no highlight")
        expect(RubySupport.highlightRanges(in: text, words: ["存在しない"]).isEmpty, "missing word means no highlight")

        // 注音 segment：命中的 segment 標記；單字跨 segment 時全部標記。
        let segments = [
            RubySegment(base: "この"),
            RubySegment(base: "放送", ruby: "ほうそう"),
            RubySegment(base: "は"),
            RubySegment(base: "面白", ruby: "おもしろ"),
            RubySegment(base: "い。")
        ]
        let flags = RubySupport.highlightFlags(for: segments, words: ["放送"])
        expect(flags == [false, true, false, false, false], "only the 放送 segment should highlight, got: \(flags)")
        // 「面白い」跨了「面白」「い。」兩個 segment，兩個都要亮。
        let crossFlags = RubySupport.highlightFlags(for: segments, words: ["面白い"])
        expect(crossFlags == [false, false, false, true, true], "a word spanning segments should highlight both, got: \(crossFlags)")
    }

    private static func rubyRepairFixesDroppedPunctuationButNotContentMismatch() {
        // 真實案例（2026-07-05 log）：模型漏掉了「多いですが、日常的に」中間的頓號，
        // 拼接因此比原文少一個字，導致整段被判定為不可用。
        let text = "長年使っていないものも多いですが、日常的に利用する文房具はどれも役に立つものばかりです。"
        let segments = [
            RubySegment(base: "長年", ruby: "ちょうねん"),
            RubySegment(base: "使", ruby: "つか"),
            RubySegment(base: "っていないものも", ruby: ""),
            RubySegment(base: "多", ruby: "おお"),
            RubySegment(base: "いですが", ruby: ""),
            RubySegment(base: "日常的", ruby: "にちじょうてき"),
            RubySegment(base: "に", ruby: ""),
            RubySegment(base: "利用", ruby: "りよう"),
            RubySegment(base: "する", ruby: ""),
            RubySegment(base: "文房具", ruby: "ぶんぼうぐ"),
            RubySegment(base: "はどれも", ruby: ""),
            RubySegment(base: "役", ruby: "やく"),
            RubySegment(base: "に", ruby: ""),
            RubySegment(base: "立", ruby: "た"),
            RubySegment(base: "つものばかりです。", ruby: "")
        ]
        expect(!RubySupport.isUsable(segments, for: text), "precondition: dropped-punctuation output should fail strict validation")

        guard let repaired = RubySupport.repaired(segments, toMatch: text) else {
            expect(false, "repaired() should recover a paragraph that only dropped a 、")
            return
        }
        expect(RubySupport.isUsable(repaired, for: text), "repaired segments should pass strict validation")
        expect(repaired.map(\.base).joined() == text, "repaired base concatenation should equal the original text")
        expect(repaired.contains { $0.base == "、" && $0.ruby.isEmpty }, "the dropped comma should be re-inserted without ruby")

        // 反例：漢字內容真的被模型改寫（多→少），這是內容錯誤，不該被「修復」掩蓋。
        let wrongContent = [
            RubySegment(base: "長年", ruby: "ちょうねん"),
            RubySegment(base: "使", ruby: "つか"),
            RubySegment(base: "っていないものも", ruby: ""),
            RubySegment(base: "少", ruby: "すく"), // 原文是「多」，這裡被改成「少」
            RubySegment(base: "いですが、", ruby: "")
        ]
        expect(RubySupport.repaired(wrongContent, toMatch: text) == nil,
               "repaired() must not paper over an actual kanji content mismatch")

        // 反例：完全不相干的內容，理應直接回傳 nil。
        expect(RubySupport.repaired([RubySegment(base: "全然違う文章です")], toMatch: text) == nil,
               "repaired() must return nil for unrelated content")
    }

    private static func ollamaPresetSupportsLocalKeylessProvider() {
        let preset = ProviderPreset.ollama
        expect(preset.defaultBaseURL.absoluteString == "http://127.0.0.1:11434/v1",
               "Ollama preset should target the local OpenAI-compatible endpoint")
        expect(!preset.requiresAPIKey, "Ollama preset should not require an API key")
        expect(preset.defaultStructuredOutput == .jsonObject,
               "Ollama preset should default response_format on to constrain local models")
        expect(!preset.usesCuratedModelList, "Ollama should list locally installed models")
        expect(ProviderPreset.openAI.requiresAPIKey, "cloud presets should still require an API key")
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

    private static func pipelineParseAndStoreForValidationRegistersSourceAndCards() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        let url = URL(string: "https://www.lifehacker.jp/")!
        let pipeline = LearningPipeline(
            store: store,
            crawler: MockCrawler(document: CrawledDocument(
                sourceId: UUID(),
                url: url,
                title: "lifehacker",
                plainText: "記事の本文。",
                contentHash: "hash-lifehacker"
            )),
            llmClient: MockLLMClient(cardURL: url)
        )

        // 測試尚未加入的新網址：解析成功應「登記來源 + 寫入卡片」。
        let source = Source(url: url)
        let outcome = await pipeline.parseAndStoreForValidation(source: source, registerSource: true)
        expect(outcome == .stored(cardCount: 1), "validating a new URL should store the parsed card, got \(outcome)")

        let afterFirst = await store.read()
        expect(afterFirst.sources.contains(where: { $0.url == url }), "new source should be registered, not vanish")
        expect(afterFirst.cards.count == 1, "parsed card should be saved to the database")
        expect(afterFirst.documents.count == 1, "crawled document should be saved")

        // 相同內容再測一次：應判定重複、不重複建立卡片或來源。
        let dup = await pipeline.parseAndStoreForValidation(source: source, registerSource: true)
        expect(dup == .duplicate, "re-testing identical content should be a duplicate, got \(dup)")
        let afterDup = await store.read()
        expect(afterDup.cards.count == 1, "duplicate content should not add more cards")
        expect(afterDup.sources.filter { $0.url == url }.count == 1, "duplicate content should not duplicate the source")
    }

    private static func generatedArticleKindDecodingBackfillsLegacyData() throws {
        // 舊資料沒有 kind 欄位：有 paragraphs 視為短文，沒有視為擷取文章。
        let legacyExtraction = """
        {"id":"6F1F1D40-0000-4000-8000-000000000001","theme":"旅行","title":"京都","plainText":"今日は京都に行きました。","contentHash":"h1","sourceId":"6F1F1D40-0000-4000-8000-0000000000AA"}
        """
        let legacyEssay = """
        {"id":"6F1F1D40-0000-4000-8000-000000000002","theme":"生活","title":"朝","plainText":"毎朝走ります。","contentHash":"h2","sourceId":"6F1F1D40-0000-4000-8000-0000000000AA","paragraphs":[{"japanese":"毎朝走ります。","ruby":[],"translation":"每天早上跑步。"}]}
        """
        let decoder = JSONDecoder()
        let extraction = try decoder.decode(GeneratedArticle.self, from: Data(legacyExtraction.utf8))
        let essay = try decoder.decode(GeneratedArticle.self, from: Data(legacyEssay.utf8))
        expect(extraction.kind == .extraction, "legacy article without paragraphs should decode as extraction")
        expect(essay.kind == .essay, "legacy article with paragraphs should decode as essay")
        expect(extraction.resolvedParagraphs.map(\.japanese) == ["今日は京都に行きました。"], "resolvedParagraphs should split plainText for extraction articles")

        let roundTrip = try decoder.decode(GeneratedArticle.self, from: JSONEncoder().encode(essay))
        expect(roundTrip.kind == .essay, "kind should round trip through encoding")
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

    // MARK: - SyncedBaseStore

    private static func syncedBaseStoreRoundTrips() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("synced.sqlite")
        let store = SyncedBaseStore(url: url)

        let initial = try store.loadSync()
        expect(initial == nil, "loadSync should return nil when no base exists")

        let payload = Data([0x01, 0x02, 0x03, 0x04])
        try store.recordSync(payload)
        let loaded = try store.loadSync()
        expect(loaded == payload, "loadSync should return what was written")

        // Overwrite
        let payload2 = Data([0xAA, 0xBB])
        try store.recordSync(payload2)
        let reloaded = try store.loadSync()
        expect(reloaded == payload2, "recordSync should overwrite previous base")

        try store.clear()
        let afterClear = try store.loadSync()
        expect(afterClear == nil, "clear should remove the base")
    }

    // MARK: - Merger

    private static func makeSnapshot(
        settings: AppSettings? = nil,
        sources: [Source] = [],
        documents: [CrawledDocument] = [],
        cards: [LearningCard] = [],
        quizzes: [QuizQuestion] = [],
        articles: [GeneratedArticle] = []
    ) -> AppSnapshot {
        let fixedSettings = settings ?? AppSettings(updatedAt: Date(timeIntervalSince1970: 0))
        return AppSnapshot(
            settings: fixedSettings,
            sources: sources,
            documents: documents,
            cards: cards,
            quizzes: quizzes,
            generatedArticles: articles
        )
    }

    private static func makeCard(
        id: UUID = UUID(),
        word: String = "電車",
        status: CardStatus = .new,
        lastShownAt: Date? = nil,
        updatedAt: Date = Date()
    ) -> LearningCard {
        LearningCard(
            id: id,
            word: word,
            reading: "でんしゃ",
            partOfSpeech: "名詞",
            meaningZh: "電車",
            grammarNoteZh: "",
            jlptLevel: .n4,
            verbFormType: .notVerb,
            exampleJa: "例",
            exampleReading: "",
            exampleZh: "例",
            sourceUrl: URL(string: "https://example.com")!,
            status: status,
            createdAt: Date(timeIntervalSince1970: 0),
            lastShownAt: lastShownAt,
            updatedAt: updatedAt
        )
    }

    private static func makeSource(id: UUID = UUID(), url: String = "https://example.com", updatedAt: Date = Date()) -> Source {
        Source(
            id: id,
            url: URL(string: url)!,
            isEnabled: true,
            extractionPrompt: "",
            lastFetchedAt: nil,
            lastError: nil,
            updatedAt: updatedAt
        )
    }

    private static func mergerKeepsLocalOnlyChanges() throws {
        let id = UUID()
        let local = makeSnapshot(sources: [makeSource(id: id, url: "https://local.example.com")])
        let remote = makeSnapshot()
        let base = makeSnapshot()

        let result = Merger.merge3Way(local: local, remote: remote, base: base)
        expect(result.snapshot.sources.count == 1, "local-only record must survive merge")
        expect(result.snapshot.sources[0].url.absoluteString == "https://local.example.com", "local record preserved")
        expect(result.conflicts.isEmpty, "local-only change should not be flagged as conflict")
    }

    private static func mergerKeepsRemoteOnlyChanges() throws {
        let id = UUID()
        let local = makeSnapshot()
        let remote = makeSnapshot(sources: [makeSource(id: id, url: "https://remote.example.com")])
        let base = makeSnapshot()

        let result = Merger.merge3Way(local: local, remote: remote, base: base)
        expect(result.snapshot.sources.count == 1, "remote-only record must survive merge")
        expect(result.snapshot.sources[0].url.absoluteString == "https://remote.example.com", "remote record preserved")
        expect(result.conflicts.isEmpty, "remote-only change should not be flagged as conflict")
    }

    private static func mergerTakesRemoteWhenLocalEqualsBase() throws {
        let id = UUID()
        let original = makeSource(id: id, url: "https://example.com")
        let modified = makeSource(id: id, url: "https://updated.example.com", updatedAt: Date(timeIntervalSinceNow: 100))

        let local = makeSnapshot(sources: [original])
        let remote = makeSnapshot(sources: [modified])
        let base = makeSnapshot(sources: [original])

        let result = Merger.merge3Way(local: local, remote: remote, base: base)
        expect(result.snapshot.sources.count == 1, "merged should have one record")
        expect(result.snapshot.sources[0].url.absoluteString == "https://updated.example.com", "remote's change should win when local==base")
        expect(result.conflicts.isEmpty, "non-overlapping change should not be a conflict")
    }

    private static func mergerTakesLocalWhenRemoteEqualsBase() throws {
        let id = UUID()
        let original = makeSource(id: id, url: "https://example.com")
        let modified = makeSource(id: id, url: "https://updated.example.com", updatedAt: Date(timeIntervalSinceNow: 100))

        let local = makeSnapshot(sources: [modified])
        let remote = makeSnapshot(sources: [original])
        let base = makeSnapshot(sources: [original])

        let result = Merger.merge3Way(local: local, remote: remote, base: base)
        expect(result.snapshot.sources.count == 1, "merged should have one record")
        expect(result.snapshot.sources[0].url.absoluteString == "https://updated.example.com", "local's change should win when remote==base")
        expect(result.conflicts.isEmpty, "non-overlapping change should not be a conflict")
    }

    private static func mergerDetectsConflictAndResolvesByLWW() throws {
        let id = UUID()
        let base = makeSource(id: id, url: "https://example.com", updatedAt: Date(timeIntervalSince1970: 1000))
        let localChanged = makeSource(id: id, url: "https://local.example.com", updatedAt: Date(timeIntervalSince1970: 2000))
        let remoteChanged = makeSource(id: id, url: "https://remote.example.com", updatedAt: Date(timeIntervalSince1970: 3000))

        let local = makeSnapshot(sources: [localChanged])
        let remote = makeSnapshot(sources: [remoteChanged])
        let baseSnap = makeSnapshot(sources: [base])

        let result = Merger.merge3Way(local: local, remote: remote, base: baseSnap)
        expect(result.snapshot.sources.count == 1, "merged should have one record")
        expect(result.snapshot.sources[0].url.absoluteString == "https://remote.example.com", "remote has later updatedAt so it wins")
        expect(result.conflicts.count == 1, "true conflict should be recorded")
        expect(result.conflicts[0].table == .sources, "conflict table should be sources")
        expect(result.conflicts[0].resolution == .tookRemote, "conflict resolution should be tookRemote")
    }

    private static func mergerTreatsCardShallowDiffAsNonConflict() throws {
        let cardId = UUID()
        let t1 = Date(timeIntervalSince1970: 1000)
        let t2 = Date(timeIntervalSince1970: 2000)
        let base = makeCard(id: cardId, status: .new, lastShownAt: nil, updatedAt: t1)
        let localReviewed = makeCard(id: cardId, status: .reviewing, lastShownAt: t1, updatedAt: t1)
        let remoteReviewed = makeCard(id: cardId, status: .reviewing, lastShownAt: t2, updatedAt: t2)

        let local = makeSnapshot(cards: [localReviewed])
        let remote = makeSnapshot(cards: [remoteReviewed])
        let baseSnap = makeSnapshot(cards: [base])

        let result = Merger.merge3Way(local: local, remote: remote, base: baseSnap)
        expect(result.snapshot.cards.count == 1, "shallow diff should keep one card")
        expect(result.snapshot.cards[0].lastShownAt == t2, "should pick the later lastShownAt")
        expect(result.conflicts.isEmpty, "shallow diff (only status/lastShownAt) should not be a conflict")
    }

    private static func mergerDetectsSettingsConflict() throws {
        let baseSettings = AppSettings(displayIntervalMinutes: 30, updatedAt: Date(timeIntervalSince1970: 500))
        let localSettings = AppSettings(displayIntervalMinutes: 10, updatedAt: Date(timeIntervalSince1970: 1000))
        let remoteSettings = AppSettings(displayIntervalMinutes: 20, updatedAt: Date(timeIntervalSince1970: 2000))

        let local = makeSnapshot(settings: localSettings)
        let remote = makeSnapshot(settings: remoteSettings)
        let baseSnap = makeSnapshot(settings: baseSettings)

        let result = Merger.merge3Way(local: local, remote: remote, base: baseSnap)
        expect(result.snapshot.settings.displayIntervalMinutes == 20, "remote has later updatedAt, should win")
        expect(result.conflicts.count == 1, "settings conflict should be recorded")
        expect(result.conflicts[0].table == .settings, "conflict table should be settings")
        expect(result.conflicts[0].resolution == .tookRemote, "remote has later updatedAt")
    }

    private static func mergerHandlesNilBase() throws {
        let local = makeSnapshot(sources: [makeSource(url: "https://local.example.com")])
        let remote = makeSnapshot(sources: [makeSource(url: "https://remote.example.com")])
        let result = Merger.merge3Way(local: local, remote: remote, base: nil)
        expect(result.snapshot.sources.count == 2, "with no base, union of local+remote should be kept")
    }

    private static func appStoreStampsUpdatedAtOnChangedRecords() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let beforeWrite = Date()
        let sourceId = UUID()
        try await store.update { state in
            state.sources = [makeSource(id: sourceId, url: "https://example.com", updatedAt: beforeWrite)]
        }
        let firstSnapshot = await store.read()
        let initialUpdatedAt = firstSnapshot.sources[0].updatedAt
        // AppStore.update() 會 stamp 寫入時刻, 不保留 caller 給的 updatedAt
        expect(initialUpdatedAt >= beforeWrite, "newly written record should be stamped with a time at or after the write moment")

        // 模擬改 settings 但 source 沒動 → source 的 updatedAt 應保留
        let afterFirstWrite = initialUpdatedAt
        try await store.update { state in
            state.settings.displayIntervalMinutes = 5
        }
        let secondSnapshot = await store.read()
        let cardAfter = secondSnapshot.sources.first { $0.id == sourceId }
        expect(cardAfter?.updatedAt == afterFirstWrite, "unchanged record should keep its previous updatedAt")

        // 改 source 內容 → updatedAt 應重 stamp
        try await store.update { state in
            if let i = state.sources.firstIndex(where: { $0.id == sourceId }) {
                state.sources[i].url = URL(string: "https://changed.example.com")!
            }
        }
        let thirdSnapshot = await store.read()
        let changed = thirdSnapshot.sources.first { $0.id == sourceId }
        expect(changed?.url.absoluteString == "https://changed.example.com", "source should reflect update")
        expect((changed?.updatedAt ?? .distantPast) > afterFirstWrite, "modified record should get a newer updatedAt")
    }

    // MARK: - CloudKit Transport

    private static func cloudKitTransportSubmitsFirstTimeWithoutRetry() async throws {
        let backing = MockCloudKitBacking()
        let transport = CloudKitTransport(backing: backing)
        // 用整數秒的 Date, ISO8601 預設格式 (無 fractional seconds) 才能
        // 完整 round-trip。否則 sub-second 精度會在 encode/decode 之間丟失。
        let payload = DatabasePayload(
            bundleVersion: "1.0",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedBy: "test",
            snapshot: makeSnapshot()
        )

        try await transport.submit(payload)
        let snap = backing.snapshot()
        expect(snap.saveCount == 1, "first-time submit should save exactly once (no retry)")
        // JSON encode 不保證 key 順序, decode 後比對內容才準。
        let stored = snap.stored.flatMap { try? DatabasePayload.decoded(from: $0.payload) }
        expect(stored == payload, "stored payload should round-trip to the same value")
    }

    private static func cloudKitTransportRetriesOnceOnConflict() async throws {
        let backing = MockCloudKitBacking()
        let transport = CloudKitTransport(backing: backing)
        let payload = DatabasePayload(
            bundleVersion: "1.0",
            generatedAt: Date(),
            updatedBy: "test",
            snapshot: makeSnapshot()
        )

        // 第一次 save 衝突, 第二次應該成功
        backing.setNextSaveError(CloudKitBackingError.conflict(actualVersion: 99))
        try await transport.submit(payload)

        let snap = backing.snapshot()
        expect(snap.saveCount == 2, "conflict should trigger one retry (2 total save calls)")
        expect(snap.stored != nil, "after retry the store should have the payload")
    }

    private static func cloudKitTransportFetchReturnsNilWhenEmpty() async throws {
        let backing = MockCloudKitBacking()
        let transport = CloudKitTransport(backing: backing)
        let result = try await transport.fetchLatest()
        expect(result == nil, "fetchLatest should return nil when cloud has no record")
    }

    private static func cloudKitTransportFetchDecodesPayload() async throws {
        let backing = MockCloudKitBacking()
        let original = DatabasePayload(
            bundleVersion: "1.0",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedBy: "remote-mac",
            snapshot: makeSnapshot(sources: [makeSource(url: "https://remote.example.com")])
        )
        backing.setStored(CloudKitBackingStored(payload: try original.encoded(), version: 42))

        let transport = CloudKitTransport(backing: backing)
        let decoded = try await transport.fetchLatest()
        expect(decoded != nil, "fetchLatest should decode the stored payload")
        expect(decoded?.bundleVersion == "1.0", "bundleVersion should round trip")
        expect(decoded?.updatedBy == "remote-mac", "updatedBy should round trip")
        expect(decoded?.generatedAt == original.generatedAt, "generatedAt should round trip")
        expect(decoded?.snapshot.sources.first?.url.absoluteString == "https://remote.example.com", "snapshot contents should round trip")
    }

    private static func appStoreAppliesMergedSnapshot() async throws {
        // 模擬 CloudKit pull 流程: 拿到遠端 snapshot → 跑 merger → 把 merged
        // 寫回本地 store。本測試驗證「merged snapshot 透過 store.update 套用」
        // 這個新流程是對的 (之前是直接灌 raw bytes, 現在走語意層)。

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)

        // 本地有 1 筆, 遠端有 2 筆 (含本地那筆 + 一筆新增)
        let sourceId = UUID()
        let newSourceId = UUID()
        let localSnapshot = makeSnapshot(sources: [
            makeSource(id: sourceId, url: "https://local.example.com", updatedAt: Date(timeIntervalSince1970: 1000))
        ])
        let remoteSnapshot = makeSnapshot(sources: [
            makeSource(id: sourceId, url: "https://local.example.com", updatedAt: Date(timeIntervalSince1970: 2000)),
            makeSource(id: newSourceId, url: "https://added-by-remote.example.com", updatedAt: Date(timeIntervalSince1970: 2000))
        ])

        // 把 local 寫進去
        try await store.update { state in state.sources = localSnapshot.sources }

        // 跑 merger (base 假設等於 local, 模擬「兩台都從同樣的 base 開始」)
        let result = Merger.merge3Way(local: localSnapshot, remote: remoteSnapshot, base: localSnapshot)
        expect(result.snapshot.sources.count == 2, "merged should have both sources")
        expect(result.conflicts.isEmpty, "no conflict: local==base, remote only added")

        // 把 merged 套回 store
        try await store.update { state in state = result.snapshot }

        let afterMerge = await store.read()
        expect(afterMerge.sources.count == 2, "after applying merge, store should have 2 sources")
        expect(afterMerge.sources.contains(where: { $0.id == newSourceId }), "should include the source added by remote")
    }

    // MARK: - SyncCoordinator integration

    /// 起一份測試用 AppStore + SyncedBaseStore + MockCloudKitBacking + SyncCoordinator
    /// 全部放在各自獨立的 temp 目錄, 避免互相干擾。
    private static func makeTestSyncHarness(
        remoteInitial: DatabasePayload? = nil
    ) async throws -> (store: AppStore, transport: CloudKitTransport, backing: MockCloudKitBacking, syncedBase: SyncedBaseStore, conflictStore: ConflictStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("store.sqlite")
        let baseURL = dir.appendingPathComponent("store-synced.sqlite")

        let store = await AppStore(fileURL: fileURL)
        let backing = MockCloudKitBacking()
        if let initial = remoteInitial {
            backing.setStored(CloudKitBackingStored(payload: try initial.encoded(), version: 1))
        }
        let transport = CloudKitTransport(backing: backing)
        let syncedBase = SyncedBaseStore(url: baseURL)
        let conflictStore = ConflictStore(storeURL: dir.appendingPathComponent("conflicts.json"))

        return (store, transport, backing, syncedBase, conflictStore, dir)
    }

    private static func syncCoordinatorPushesLocalToCloud() async throws {
        let harness = try await makeTestSyncHarness()
        defer { try? FileManager.default.removeItem(at: harness.dir) }

        let sourceId = UUID()
        try await harness.store.update { state in
            state.sources = [makeSource(id: sourceId, url: "https://local.example.com", updatedAt: Date(timeIntervalSince1970: 1000))]
        }

        let coordinator = SyncCoordinator(
            transport: harness.transport,
            store: harness.store,
            syncedBase: harness.syncedBase,
            conflictStore: harness.conflictStore
        )
        try await coordinator.pushIfNeeded()

        let snap = harness.backing.snapshot()
        expect(snap.saveCount == 1, "first push should hit cloud once")
        expect(snap.stored != nil, "cloud should have the payload after push")
        let stored = snap.stored.flatMap { try? DatabasePayload.decoded(from: $0.payload) }
        expect(stored?.snapshot.sources.first?.id == sourceId, "cloud should have the local source")

        // synced base 也應該被更新
        let baseBytes = try harness.syncedBase.loadSync()
        expect(baseBytes != nil, "synced base should be written after successful push")
    }

    /// 安全網: local 完全沒有使用者內容時不可 push，避免空檔覆蓋雲端資料。
    private static func syncCoordinatorSkipsPushWhenLocalEmpty() async throws {
        let harness = try await makeTestSyncHarness()
        defer { try? FileManager.default.removeItem(at: harness.dir) }

        // 不寫入任何內容 → store 是空的。
        let coordinator = SyncCoordinator(
            transport: harness.transport,
            store: harness.store,
            syncedBase: harness.syncedBase,
            conflictStore: harness.conflictStore
        )
        try await coordinator.pushIfNeeded()

        let snap = harness.backing.snapshot()
        expect(snap.saveCount == 0, "empty local must not push to cloud")
        expect(snap.stored == nil, "cloud must stay untouched when local is empty")
    }

    private static func syncCoordinatorPullsAndMergesRemoteChanges() async throws {
        // 模擬「另一台 Mac 加了一筆 source」, 然後本機 pull 跟 merge。
        // 兩台對於「既有的那筆」內容完全一致 (同樣的 id / url), 但因為
        // AppStore 會 stamp updatedAt 到「現在」, 兩邊的 updatedAt 不會
        // 完全相等 → 走 LWW 分支, 視為一次「無實質衝突的更新」, merged
        // 結果應有 2 筆 source (既有那筆 LWW 解決, 新那筆加進來)。
        let sourceId = UUID()
        let newSourceId = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let remotePayload = DatabasePayload(
            bundleVersion: "1.0",
            generatedAt: now,
            updatedBy: "remote-mac",
            snapshot: makeSnapshot(sources: [
                makeSource(id: sourceId, url: "https://local.example.com", updatedAt: now),
                makeSource(id: newSourceId, url: "https://added-by-remote.example.com", updatedAt: now)
            ])
        )
        let harness = try await makeTestSyncHarness(remoteInitial: remotePayload)
        defer { try? FileManager.default.removeItem(at: harness.dir) }

        // 本地先寫一筆, 跟 remote 既有的那筆同 id / url
        try await harness.store.update { state in
            state.sources = [makeSource(id: sourceId, url: "https://local.example.com", updatedAt: now)]
        }

        let coordinator = SyncCoordinator(
            transport: harness.transport,
            store: harness.store,
            syncedBase: harness.syncedBase,
            conflictStore: harness.conflictStore
        )
        try await coordinator.pullAndMerge()

        let afterPull = await harness.store.read()
        expect(afterPull.sources.count == 2, "after pull, local should have 2 sources (existing LWW + new from remote)")
        expect(afterPull.sources.contains(where: { $0.id == newSourceId }), "should include the new source from remote")
    }

    private static func syncCoordinatorMergesConflictingChanges() async throws {
        // 模擬「兩台都改了同一筆 source 的 url」, 內容跟 base 都不一樣 →
        // 衝突偵測, 走 LWW。具體誰贏不重要 (AppStore 會 stamp updatedAt
        // 到「現在」, 測試無法保證 local vs remote 哪個時間較新), 只要:
        // 1. conflict 有被記下來
        // 2. merged 後的 url 是 local 或 remote 其中之一, 不是 base
        let sourceId = UUID()
        let baseT = Date(timeIntervalSince1970: 1_700_000_000)
        let baseSnapshot = makeSnapshot(sources: [
            makeSource(id: sourceId, url: "https://base.example.com", updatedAt: baseT)
        ])
        let remotePayload = DatabasePayload(
            bundleVersion: "1.0",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            updatedBy: "remote",
            snapshot: makeSnapshot(sources: [
                makeSource(id: sourceId, url: "https://remote.example.com", updatedAt: Date(timeIntervalSince1970: 1_700_000_500))
            ])
        )

        let harness = try await makeTestSyncHarness(remoteInitial: remotePayload)
        defer { try? FileManager.default.removeItem(at: harness.dir) }

        // 本地寫入: 跟 base 同 id 但 url 改成 local.example.com
        try await harness.store.update { state in
            state.sources = [makeSource(id: sourceId, url: "https://local.example.com", updatedAt: baseT)]
        }
        // synced base 寫成 base
        try harness.syncedBase.recordSync(try DatabasePayload(
            bundleVersion: "1.0", generatedAt: baseT, updatedBy: "test", snapshot: baseSnapshot
        ).encoded())

        let coordinator = SyncCoordinator(
            transport: harness.transport,
            store: harness.store,
            syncedBase: harness.syncedBase,
            conflictStore: harness.conflictStore
        )
        try await coordinator.pullAndMerge()

        let conflictCount = await harness.conflictStore.records.count
        expect(conflictCount == 1, "should record one conflict for the source (url differs on both sides)")
        let conflicts = await harness.conflictStore.records
        expect(conflicts.first?.table == .sources, "conflict should be in sources table")

        let afterPull = await harness.store.read()
        let mergedURL = afterPull.sources.first?.url.absoluteString
        expect(mergedURL == "https://local.example.com" || mergedURL == "https://remote.example.com", "merged url should be local or remote, not base")
        expect(mergedURL != "https://base.example.com", "merged url should NOT be the base value (it was overwritten)")
    }

    // MARK: - 刪除同步

    private static func appStoreAutoDetectsDeletedSource() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let keepId = UUID()
        let dropId = UUID()
        try await store.update { state in
            state.sources = [
                makeSource(id: keepId, url: "https://keep.example.com"),
                makeSource(id: dropId, url: "https://drop.example.com")
            ]
        }

        // 使用者刪掉其中一筆
        try await store.update { state in
            state.sources.removeAll { $0.id == dropId }
        }

        let after = await store.read()
        expect(after.sources.count == 1, "刪除後 sources 應該剩 1 筆")
        expect(after.sources.first?.id == keepId, "留下來的應該是 keepId")
        expect(after.deletedSources.contains(dropId), "dropId 應該被加進 deletedSources tombstones")
        expect(!after.deletedSources.contains(keepId), "keepId 不應該在 deletedSources")
    }

    private static func appStoreUndeleteRemovesFromDeletedSet() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("store.sqlite")
        let store = await AppStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let id = UUID()
        try await store.update { state in
            state.sources = [makeSource(id: id, url: "https://will-be-deleted.example.com")]
        }
        try await store.update { state in
            state.sources.removeAll { $0.id == id }
        }
        let afterDelete = await store.read()
        expect(afterDelete.deletedSources.contains(id), "刪除後要在 deleted 清單")

        // 使用者又把同一個 id 加回來 (un-delete)
        try await store.update { state in
            state.sources = [makeSource(id: id, url: "https://restored.example.com")]
        }
        let afterUndelete = await store.read()
        expect(afterUndelete.sources.count == 1, "un-delete 後 sources 應該有 1 筆")
        expect(afterUndelete.sources.first?.url.absoluteString == "https://restored.example.com", "un-delete 後 url 應該是新值")
        expect(!afterUndelete.deletedSources.contains(id), "un-delete 後不該再在 deleted 清單")
    }

    private static func mergerAppliesDeletionsToAllTables() throws {
        // 驗證 deleted* 清單的 union 會把 record 從合併結果拿掉
        let sourceID = UUID()
        let cardID = UUID()
        let docHash = "hash-for-deleted-doc"
        let base = makeSnapshot(
            sources: [makeSource(id: sourceID, url: "https://a.example.com")],
            documents: [CrawledDocument(sourceId: sourceID, url: URL(string: "https://a.example.com")!, title: "A", plainText: "text", contentHash: docHash)],
            cards: [makeCard(id: cardID, word: "old")]
        )

        // 遠端把那 3 個 record 都刪了 (sources 陣列拿掉, deleted 清單加 ID)
        let remote = AppSnapshot(
            sources: [],
            documents: [],
            cards: [],
            deletedSources: [sourceID],
            deletedDocuments: [docHash],
            deletedCards: [cardID]
        )

        let result = Merger.merge3Way(local: makeSnapshot(), remote: remote, base: base)
        expect(result.snapshot.sources.isEmpty, "deleted source 應該從合併結果拿掉")
        expect(result.snapshot.documents.isEmpty, "deleted document 應該從合併結果拿掉")
        expect(result.snapshot.cards.isEmpty, "deleted card 應該從合併結果拿掉")
        expect(result.snapshot.deletedSources.contains(sourceID), "deletedSources 應保留 tombstone")
        expect(result.snapshot.deletedDocuments.contains(docHash), "deletedDocuments 應保留 tombstone")
        expect(result.snapshot.deletedCards.contains(cardID), "deletedCards 應保留 tombstone")
    }

    private static func syncCoordinatorPropagatesDeletionToOtherMac() async throws {
        // 模擬「Mac A 刪了一筆 source → push → 雲端更新 → Mac B pull → 拿掉本地那筆」
        let sourceId = UUID()
        let baseT = Date(timeIntervalSince1970: 1_700_000_000)
        let baseSnapshot = makeSnapshot(sources: [
            makeSource(id: sourceId, url: "https://will-be-deleted.example.com", updatedAt: baseT)
        ])

        // 模擬 Mac A 刪掉 sourceId: 本地拿掉 + deletedSources 加上
        let macA = DatabasePayload(
            bundleVersion: "1.0",
            generatedAt: Date(timeIntervalSince1970: 1_700_001_000),
            updatedBy: "mac-a",
            snapshot: AppSnapshot(
                sources: [],
                deletedSources: [sourceId]
            )
        )

        let harness = try await makeTestSyncHarness(remoteInitial: macA)
        defer { try? FileManager.default.removeItem(at: harness.dir) }

        // Mac B 還沒 pull, 本地有那筆
        try await harness.store.update { state in
            state.sources = baseSnapshot.sources
        }
        // synced base 對齊到 macA 推送前
        try harness.syncedBase.recordSync(try DatabasePayload(
            bundleVersion: "1.0", generatedAt: baseT, updatedBy: "test", snapshot: baseSnapshot
        ).encoded())

        let coordinator = SyncCoordinator(
            transport: harness.transport,
            store: harness.store,
            syncedBase: harness.syncedBase,
            conflictStore: harness.conflictStore
        )
        try await coordinator.pullAndMerge()

        let afterPull = await harness.store.read()
        expect(afterPull.sources.isEmpty, "Mac B pull 後本地 source 應該被刪掉")
        expect(afterPull.deletedSources.contains(sourceId), "Mac B 應收到 deleted tombstones")
    }

    // MARK: - Conflict 細節

    private static func mergerConflictRecordContainsLocalRemoteBaseJSON() throws {
        // 衝突時 Merger 應該把 local / remote / base 的 JSON 都序列化進 ConflictRecord
        // 給 UI side-by-side 顯示用
        let id = UUID()
        let baseT = Date(timeIntervalSince1970: 1_700_000_000)
        let localT = Date(timeIntervalSince1970: 1_700_000_500)
        let remoteT = Date(timeIntervalSince1970: 1_700_001_000)

        let base = makeSnapshot(sources: [
            makeSource(id: id, url: "https://base.example.com", updatedAt: baseT)
        ])
        let local = makeSnapshot(sources: [
            makeSource(id: id, url: "https://local.example.com", updatedAt: localT)
        ])
        let remote = makeSnapshot(sources: [
            makeSource(id: id, url: "https://remote.example.com", updatedAt: remoteT)
        ])

        let result = Merger.merge3Way(local: local, remote: remote, base: base)
        expect(result.conflicts.count == 1, "應有一筆衝突")
        let conflict = result.conflicts[0]
        expect(conflict.table == .sources, "衝突表是 sources")
        expect(!conflict.localValue.isEmpty, "localValue 應有 JSON")
        expect(!conflict.remoteValue.isEmpty, "remoteValue 應有 JSON")
        expect(!conflict.baseValue!.isEmpty, "baseValue 應有 JSON")

        // decode 回去應該拿回原本的值
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let localDecoded = try decoder.decode(Source.self, from: conflict.localValue)
        let remoteDecoded = try decoder.decode(Source.self, from: conflict.remoteValue)
        let baseDecoded = try decoder.decode(Source.self, from: conflict.baseValue!)
        expect(localDecoded.url.absoluteString == "https://local.example.com", "local JSON 應 decode 回正確的 url")
        expect(remoteDecoded.url.absoluteString == "https://remote.example.com", "remote JSON 應 decode 回正確的 url")
        expect(baseDecoded.url.absoluteString == "https://base.example.com", "base JSON 應 decode 回正確的 url")
    }

    private static func conflictStorePersistsAndReloads() async throws {
        // 驗證 ConflictStore 寫進磁碟後, 重新 init 能讀回來
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("conflicts.json")

        let store1 = ConflictStore(storeURL: url)
        let id = UUID()
        let conflict = ConflictRecord(
            id: id,
            table: .sources,
            recordId: id.uuidString,
            resolution: .tookRemote,
            localValue: Data("\"local\"".utf8),
            remoteValue: Data("\"remote\"".utf8),
            baseValue: Data("\"base\"".utf8)
        )
        await store1.replace(with: [conflict])
        let count1 = await store1.records.count
        expect(count1 == 1, "寫入後應有 1 筆")

        // 重新 init, 應讀到剛才寫入的
        let store2 = ConflictStore(storeURL: url)
        let count2 = await store2.records.count
        expect(count2 == 1, "重新 init 後應讀到 1 筆")
        let loaded = await store2.records.first
        expect(loaded?.id == id, "id 應一致")
        expect(loaded?.table == .sources, "table 應一致")

        // markResolved 也要持久化
        await store2.markResolved(id)
        let store3 = ConflictStore(storeURL: url)
        let resolved = await store3.records.first
        expect(resolved?.isResolved == true, "markResolved 應持久化")
    }
}

// MARK: - Test helpers

/// 用 class 裝可變 flag, 避免在 @Sendable closure 裡 mutate captured var。
private final class FlagBox: @unchecked Sendable {
    var value: Bool = false
}

/// 可程控的 in-memory backing, 測試用。可指定 fetch / save 行為, 模擬
/// 衝突、網路錯誤等情境。
private final class MockCloudKitBacking: CloudKitBacking, @unchecked Sendable {
    private struct State {
        var stored: CloudKitBackingStored?
        var nextSaveError: Error?
        var saveCallCount = 0
        var subscriptionRegistered = false
    }
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    func setStored(_ value: CloudKitBackingStored?) {
        lock.withLock { $0.stored = value }
    }

    func setNextSaveError(_ error: Error?) {
        lock.withLock { $0.nextSaveError = error }
    }

    func snapshot() -> (stored: CloudKitBackingStored?, saveCount: Int, subscribed: Bool) {
        lock.withLock { ($0.stored, $0.saveCallCount, $0.subscriptionRegistered) }
    }

    func fetchCurrent() async throws -> CloudKitBackingStored? {
        lock.withLock { $0.stored }
    }

    func save(payload: Data, expectedVersion: Int?) async throws -> Int {
        let (newVersion, stored) = try lock.withLock { state -> (Int, CloudKitBackingStored) in
            state.saveCallCount += 1
            if let error = state.nextSaveError {
                state.nextSaveError = nil
                throw error
            }
            let version = state.saveCallCount * 7
            let entry = CloudKitBackingStored(payload: payload, version: version)
            state.stored = entry
            return (version, entry)
        }
        _ = stored
        return newVersion
    }

    func registerSubscription() async throws {
        lock.withLock { $0.subscriptionRegistered = true }
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
                exampleReading: "でんしゃにのります。",
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

/// 測試用的 URLProtocol，讓 SourceConnectionTester 的請求改由 handler 回應，無需真實網路。
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// 回傳 (statusCode, body, contentType) 或 throw 以模擬傳輸錯誤。
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, data, contentType) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
