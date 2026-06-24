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

    private static func durationMilliseconds(since startedAt: Date) -> Int {
        Int((max(Date().timeIntervalSince(startedAt), 0) * 1000).rounded())
    }
}
