import Foundation

public enum AIArticleOutcome: Sendable {
    case generated(GeneratedArticle)
    case duplicate
    case failed(String)

    public var generatedArticle: GeneratedArticle? {
        if case .generated(let article) = self { return article }
        return nil
    }
}

public enum ManualCardOutcome: Sendable {
    case generated(count: Int)
    case empty
    case failed(String)
}

public struct CardBackfillOutcome: Equatable, Sendable {
    public var processedDocuments: Int
    public var updatedCards: Int
    public var skippedDocuments: Int
    public var failures: [String]

    public init(processedDocuments: Int = 0, updatedCards: Int = 0, skippedDocuments: Int = 0, failures: [String] = []) {
        self.processedDocuments = processedDocuments
        self.updatedCards = updatedCards
        self.skippedDocuments = skippedDocuments
        self.failures = failures
    }
}

public actor LearningPipeline {
    private let store: AppStore
    private let crawler: Crawling
    private let llmClient: LLMClient

    public init(store: AppStore, crawler: Crawling = WebCrawler(), llmClient: LLMClient = OpenAICompatibleLLMClient()) {
        self.store = store
        self.crawler = crawler
        self.llmClient = llmClient
    }

    public func refreshEnabledSources() async {
        let traceId = UUID().uuidString
        await AITraceContext.$traceId.withValue(traceId) {
            await AITraceContext.$flow.withValue("refreshEnabledSources") {
                await refreshEnabledSourcesWithTrace()
            }
        }
    }

    public func backfillExistingCards(limitToIncompleteCards: Bool = true) async -> CardBackfillOutcome {
        let traceId = UUID().uuidString
        return await AITraceContext.$traceId.withValue(traceId) {
            await AITraceContext.$flow.withValue("backfillExistingCards") {
                await backfillExistingCardsWithTrace(limitToIncompleteCards: limitToIncompleteCards)
            }
        }
    }

    private func backfillExistingCardsWithTrace(limitToIncompleteCards: Bool) async -> CardBackfillOutcome {
        let startedAt = Date()
        let snapshot = await store.read()
        var outcome = CardBackfillOutcome()
        await AIRequestLogStore.shared.appendEvent(
            "flow.start",
            operation: "backfillExistingCards",
            message: "Regenerate stored documents with current prompt to backfill structured card fields.",
            input: [
                "documentCount": "\(snapshot.documents.count)",
                "limitToIncompleteCards": "\(limitToIncompleteCards)"
            ]
        )

        for document in snapshot.documents {
            let existingCards = snapshot.cards.filter { $0.sourceUrl == document.url }
            let candidates = limitToIncompleteCards ? existingCards.filter(\.needsStructuredBackfill) : existingCards
            guard !candidates.isEmpty else {
                outcome.skippedDocuments += 1
                continue
            }

            let sourcePrompt = snapshot.sources.first(where: { $0.id == document.sourceId })?.extractionPrompt
            let prompt = (sourcePrompt?.isEmpty == false) ? sourcePrompt! : snapshot.settings.defaultExtractionPrompt
            do {
                let generated = try await llmClient.generateCards(document: document, sourcePrompt: prompt, settings: snapshot.settings)
                let updatedCount = try await mergeBackfilledCards(generated, for: document, oldCards: candidates)
                outcome.processedDocuments += 1
                outcome.updatedCards += updatedCount
            } catch {
                outcome.failures.append("\(document.title): \(error.localizedDescription)")
                try? await store.update { state in
                    if let index = state.sources.firstIndex(where: { $0.id == document.sourceId }) {
                        state.sources[index].lastError = error.localizedDescription
                    }
                }
            }
        }

        await AIRequestLogStore.shared.appendEvent(
            "flow.completed",
            operation: "backfillExistingCards",
            output: [
                "processedDocuments": "\(outcome.processedDocuments)",
                "updatedCards": "\(outcome.updatedCards)",
                "skippedDocuments": "\(outcome.skippedDocuments)",
                "failureCount": "\(outcome.failures.count)"
            ],
            durationMilliseconds: Self.durationMilliseconds(since: startedAt)
        )
        return outcome
    }

    private func mergeBackfilledCards(_ generated: [LearningCard], for document: CrawledDocument, oldCards: [LearningCard]) async throws -> Int {
        guard !generated.isEmpty else { return 0 }
        let generatedByKey = Dictionary(grouping: generated, by: Self.backfillKey)
        let generatedByWord = Dictionary(grouping: generated, by: Self.normalizedWord)
        let replacements = Dictionary(uniqueKeysWithValues: oldCards.compactMap { oldCard -> (UUID, LearningCard)? in
            let key = Self.backfillKey(oldCard)
            let replacement = generatedByKey[key]?.first ?? generatedByWord[Self.normalizedWord(oldCard)]?.first
            guard let replacement else { return nil }
            let merged = oldCard.mergingStructuredFields(from: replacement, sourceURL: document.url)
            return merged == oldCard ? nil : (oldCard.id, merged)
        })
        guard !replacements.isEmpty else { return 0 }
        try await store.update { state in
            for index in state.cards.indices {
                if let replacement = replacements[state.cards[index].id] {
                    state.cards[index] = replacement
                }
            }
        }
        return replacements.count
    }

    private func refreshEnabledSourcesWithTrace() async {
        let startedAt = Date()
        let snapshot = await store.read()
        let enabledSources = snapshot.sources.filter { source in
            source.isEnabled && !AISource.isSentinelSource(source)
        }
        await AIRequestLogStore.shared.appendEvent(
            "flow.start",
            operation: "refreshEnabledSources",
            message: "Start refreshing enabled web sources.",
            input: [
                "enabledSourceCount": "\(enabledSources.count)",
                "totalSourceCount": "\(snapshot.sources.count)"
            ]
        )

        for source in enabledSources {
            let sourceStartedAt = Date()
            await AIRequestLogStore.shared.appendEvent(
                "source.start",
                operation: "refreshSource",
                input: [
                    "sourceId": source.id.uuidString,
                    "sourceURL": source.url.absoluteString
                ]
            )
            do {
                let document = try await crawler.crawl(source: source)
                await AIRequestLogStore.shared.appendEvent(
                    "source.crawled",
                    operation: "crawlSource",
                    input: [
                        "sourceId": source.id.uuidString,
                        "sourceURL": source.url.absoluteString
                    ],
                    output: [
                        "title": document.title,
                        "contentHash": document.contentHash,
                        "plainTextCharacters": "\(document.plainText.count)"
                    ],
                    durationMilliseconds: Self.durationMilliseconds(since: sourceStartedAt)
                )
                if snapshot.documents.contains(where: { $0.contentHash == document.contentHash }) {
                    try? await store.update { state in
                        if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                            state.sources[index].lastFetchedAt = Date()
                            state.sources[index].lastError = nil
                        }
                    }
                    await AIRequestLogStore.shared.appendEvent(
                        "source.duplicate",
                        operation: "refreshSource",
                        message: "Document content hash already exists; skipped card generation.",
                        input: [
                            "sourceId": source.id.uuidString,
                            "sourceURL": source.url.absoluteString,
                            "contentHash": document.contentHash
                        ],
                        durationMilliseconds: Self.durationMilliseconds(since: sourceStartedAt)
                    )
                    continue
                }

                let prompt = source.extractionPrompt.isEmpty ? snapshot.settings.defaultExtractionPrompt : source.extractionPrompt
                let cards = try await llmClient.generateCards(document: document, sourcePrompt: prompt, settings: snapshot.settings)
                try await store.update { state in
                    state.documents.append(document)
                    state.cards.append(contentsOf: cards)
                    if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                        state.sources[index].lastFetchedAt = Date()
                        state.sources[index].lastError = nil
                    }
                }
                await AIRequestLogStore.shared.appendEvent(
                    "source.completed",
                    operation: "refreshSource",
                    input: [
                        "sourceId": source.id.uuidString,
                        "sourceURL": source.url.absoluteString,
                        "contentHash": document.contentHash
                    ],
                    output: [
                        "cardCount": "\(cards.count)"
                    ],
                    durationMilliseconds: Self.durationMilliseconds(since: sourceStartedAt)
                )
            } catch {
                try? await store.update { state in
                    if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                        state.sources[index].lastError = error.localizedDescription
                    }
                }
                await AIRequestLogStore.shared.appendEvent(
                    "source.failed",
                    operation: "refreshSource",
                    input: [
                        "sourceId": source.id.uuidString,
                        "sourceURL": source.url.absoluteString
                    ],
                    durationMilliseconds: Self.durationMilliseconds(since: sourceStartedAt),
                    errorSummary: error.localizedDescription
                )
            }
        }
        await AIRequestLogStore.shared.appendEvent(
            "flow.completed",
            operation: "refreshEnabledSources",
            output: [
                "processedSourceCount": "\(enabledSources.count)"
            ],
            durationMilliseconds: Self.durationMilliseconds(since: startedAt)
        )
    }

    /// 「驗證來源」測試 AI 解析的結果。
    public enum ValidationParseOutcome: Sendable, Equatable {
        /// 成功解析並寫入 DB，回報新增的卡片數。
        case stored(cardCount: Int)
        /// 內容與 DB 既有文件相同，未重複解析或建立卡片。
        case duplicate
        /// 爬取或解析失敗。
        case failed(message: String)
    }

    /// 為「驗證來源」實際抓取內容並呼叫 provider 解析，成功就把文件與卡片寫入 DB
    /// （沿用排程刷新的 contentHash 去重）。`registerSource` 為 true 時（測試尚未加入的
    /// 新網址），在非失敗情況下把來源一併加進清單。
    public func parseAndStoreForValidation(source: Source, registerSource: Bool) async -> ValidationParseOutcome {
        do {
            let snapshot = await store.read()
            let settings = snapshot.settings
            let document = try await crawler.crawl(source: source)

            // 內容與既有文件重複：不重存卡片，但仍視需要登記來源。
            if snapshot.documents.contains(where: { $0.contentHash == document.contentHash }) {
                if registerSource {
                    try await store.update { state in
                        if !state.sources.contains(where: { $0.url == source.url }) {
                            state.sources.append(source)
                        }
                    }
                }
                return .duplicate
            }

            let prompt = source.extractionPrompt.isEmpty ? settings.defaultExtractionPrompt : source.extractionPrompt
            let cards = try await llmClient.generateCards(document: document, sourcePrompt: prompt, settings: settings)
            try await store.update { state in
                if registerSource, !state.sources.contains(where: { $0.url == source.url }) {
                    state.sources.append(source)
                }
                state.documents.append(document)
                state.cards.append(contentsOf: cards)
                if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                    state.sources[index].lastFetchedAt = Date()
                    state.sources[index].lastError = nil
                }
            }
            return .stored(cardCount: cards.count)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failed(message: message)
        }
    }

    @discardableResult
    public func generateAIArticleNow(theme: String? = nil) async -> AIArticleOutcome {
        let traceId = UUID().uuidString
        return await AITraceContext.$traceId.withValue(traceId) {
            await AITraceContext.$flow.withValue("generateAIArticleNow") {
                await generateAIArticleNowWithTrace(theme: theme)
            }
        }
    }

    @discardableResult
    private func generateAIArticleNowWithTrace(theme: String? = nil) async -> AIArticleOutcome {
        let startedAt = Date()
        let snapshot = await store.read()
        let levels = snapshot.settings.aiArticleLevels.isEmpty ? JLPTLevel.allCases : snapshot.settings.aiArticleLevels
        let explicitTheme = theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedTheme = snapshot.settings.aiArticleCustomTheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTheme: String = !explicitTheme.isEmpty ? explicitTheme : storedTheme
        await AIRequestLogStore.shared.appendEvent(
            "flow.start",
            operation: "generateAIArticleNow",
            input: [
                "theme": normalizedTheme,
                "jlptLevels": levels.map(\.rawValue).joined(separator: ",")
            ]
        )

        do {
            let draft = try await llmClient.generateArticle(theme: normalizedTheme, jlptLevels: levels, settings: snapshot.settings)
            let contentHash = ContentHash.sha256(draft.text)
            let levelLabels = levels.map(\.rawValue).joined(separator: "、")
            let extractionPrompt = AISource.makeExtractionPrompt(theme: draft.theme, levels: levelLabels)
            await AIRequestLogStore.shared.appendEvent(
                "article.generated",
                operation: "generateArticle",
                output: [
                    "theme": draft.theme,
                    "title": draft.title,
                    "contentHash": contentHash,
                    "textCharacters": "\(draft.text.count)"
                ]
            )

            await store.ensureAISentinelSource(extractionPrompt: extractionPrompt)

            let syntheticURL = URL(string: "ai-article://\(contentHash.prefix(12))") ?? AISource.sentinelURL
            let document = CrawledDocument(
                sourceId: AISource.sentinelSourceId,
                url: syntheticURL,
                title: draft.title,
                plainText: draft.text,
                contentHash: contentHash
            )

            if snapshot.documents.contains(where: { $0.contentHash == contentHash }) {
                await AIRequestLogStore.shared.appendEvent(
                    "flow.duplicate",
                    operation: "generateAIArticleNow",
                    message: "Generated article content hash already exists.",
                    input: ["contentHash": contentHash],
                    durationMilliseconds: Self.durationMilliseconds(since: startedAt)
                )
                return .duplicate
            }

            let cards = try await llmClient.generateCards(
                document: document,
                sourcePrompt: extractionPrompt,
                settings: snapshot.settings
            )

            let article = GeneratedArticle(
                theme: draft.theme,
                jlptLevels: levels,
                title: draft.title,
                plainText: draft.text,
                contentHash: contentHash,
                sourceId: AISource.sentinelSourceId,
                generatedAt: Date(),
                cardCount: cards.count
            )

            try await store.update { state in
                state.documents.append(document)
                state.cards.append(contentsOf: cards)
                state.generatedArticles.insert(article, at: 0)
                if let index = state.sources.firstIndex(where: { $0.id == AISource.sentinelSourceId }) {
                    state.sources[index].lastFetchedAt = Date()
                    state.sources[index].lastError = nil
                    state.sources[index].extractionPrompt = extractionPrompt
                }
            }
            await AIRequestLogStore.shared.appendEvent(
                "flow.completed",
                operation: "generateAIArticleNow",
                output: [
                    "title": article.title,
                    "contentHash": article.contentHash,
                    "cardCount": "\(cards.count)"
                ],
                durationMilliseconds: Self.durationMilliseconds(since: startedAt)
            )
            return .generated(article)
        } catch {
            try? await store.update { state in
                if let index = state.sources.firstIndex(where: { $0.id == AISource.sentinelSourceId }) {
                    state.sources[index].lastError = error.localizedDescription
                }
            }
            await AIRequestLogStore.shared.appendEvent(
                "flow.failed",
                operation: "generateAIArticleNow",
                durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                errorSummary: error.localizedDescription
            )
            return .failed(error.localizedDescription)
        }
    }

    /// 由使用者貼上的文字（文章或單字清單）產生學習卡。
    public func generateCardsFromText(_ rawText: String, instruction: String = "") async -> ManualCardOutcome {
        let traceId = UUID().uuidString
        return await AITraceContext.$traceId.withValue(traceId) {
            await AITraceContext.$flow.withValue("generateCardsFromText") {
                await generateCardsFromTextWithTrace(rawText, instruction: instruction)
            }
        }
    }

    private func generateCardsFromTextWithTrace(_ rawText: String, instruction: String) async -> ManualCardOutcome {
        let startedAt = Date()
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failed("請先貼上文字內容") }

        let snapshot = await store.read()
        let contentHash = ContentHash.sha256(text)
        await AIRequestLogStore.shared.appendEvent(
            "flow.start",
            operation: "generateCardsFromText",
            input: [
                "contentHash": contentHash,
                "textCharacters": "\(text.count)"
            ]
        )

        let syntheticURL = URL(string: "manual-input://\(contentHash.prefix(12))") ?? AISource.sentinelURL
        let document = CrawledDocument(
            sourceId: AISource.sentinelSourceId,
            url: syntheticURL,
            title: "手動輸入",
            plainText: text,
            contentHash: contentHash
        )

        do {
            await store.ensureAISentinelSource(extractionPrompt: AISource.sentinelExtractionPrompt)

            let cards = try await llmClient.generateManualCards(
                text: text,
                instruction: instruction,
                sourceURL: syntheticURL,
                settings: snapshot.settings
            )

            guard !cards.isEmpty else {
                await AIRequestLogStore.shared.appendEvent(
                    "flow.empty",
                    operation: "generateCardsFromText",
                    message: "No cards produced from manual text.",
                    durationMilliseconds: Self.durationMilliseconds(since: startedAt)
                )
                return .empty
            }

            try await store.update { state in
                if !state.documents.contains(where: { $0.contentHash == contentHash }) {
                    state.documents.append(document)
                }
                state.cards.append(contentsOf: cards)
            }
            await AIRequestLogStore.shared.appendEvent(
                "flow.completed",
                operation: "generateCardsFromText",
                output: ["cardCount": "\(cards.count)"],
                durationMilliseconds: Self.durationMilliseconds(since: startedAt)
            )
            return .generated(count: cards.count)
        } catch {
            await AIRequestLogStore.shared.appendEvent(
                "flow.failed",
                operation: "generateCardsFromText",
                durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                errorSummary: error.localizedDescription
            )
            return .failed(error.localizedDescription)
        }
    }

    private static func durationMilliseconds(since startedAt: Date) -> Int {
        Int((max(Date().timeIntervalSince(startedAt), 0) * 1000).rounded())
    }

    private static func backfillKey(_ card: LearningCard) -> String {
        "\(normalizedWord(card))|\(card.reading.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private static func normalizedWord(_ card: LearningCard) -> String {
        card.word.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public extension LearningCard {
    var needsStructuredBackfill: Bool {
        reading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || meaningZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || grammarNoteZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || jlptLevel == .unknown
            || verbFormType == .unknown
            || exampleJa.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || exampleReading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || exampleZh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func mergingStructuredFields(from regenerated: LearningCard, sourceURL: URL) -> LearningCard {
        var merged = self
        merged.reading = regenerated.reading
        merged.partOfSpeech = regenerated.partOfSpeech
        merged.meaningZh = regenerated.meaningZh
        merged.grammarNoteZh = regenerated.grammarNoteZh
        merged.jlptLevel = regenerated.jlptLevel
        merged.verbFormType = regenerated.verbFormType
        merged.exampleJa = regenerated.exampleJa
        merged.exampleReading = regenerated.exampleReading
        merged.exampleZh = regenerated.exampleZh
        merged.sourceUrl = sourceURL
        return merged
    }
}
