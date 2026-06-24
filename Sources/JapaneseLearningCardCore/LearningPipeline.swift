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
        let snapshot = await store.read()
        let enabledSources = snapshot.sources.filter(\.isEnabled)

        for source in enabledSources {
            do {
                let document = try await crawler.crawl(source: source)
                if snapshot.documents.contains(where: { $0.contentHash == document.contentHash }) {
                    try? await store.update { state in
                        if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                            state.sources[index].lastFetchedAt = Date()
                            state.sources[index].lastError = nil
                        }
                    }
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
            } catch {
                try? await store.update { state in
                    if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                        state.sources[index].lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    @discardableResult
    public func generateAIArticleNow(theme: String? = nil) async -> AIArticleOutcome {
        let snapshot = await store.read()
        let levels = snapshot.settings.aiArticleLevels.isEmpty ? JLPTLevel.allCases : snapshot.settings.aiArticleLevels
        let explicitTheme = theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedTheme = snapshot.settings.aiArticleCustomTheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTheme: String = !explicitTheme.isEmpty ? explicitTheme : storedTheme

        do {
            let draft = try await llmClient.generateArticle(theme: normalizedTheme, jlptLevels: levels, settings: snapshot.settings)
            let contentHash = ContentHash.sha256(draft.text)
            let levelLabels = levels.map(\.rawValue).joined(separator: "、")
            let extractionPrompt = AISource.makeExtractionPrompt(theme: draft.theme, levels: levelLabels)

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
            return .generated(article)
        } catch {
            try? await store.update { state in
                if let index = state.sources.firstIndex(where: { $0.id == AISource.sentinelSourceId }) {
                    state.sources[index].lastError = error.localizedDescription
                }
            }
            return .failed(error.localizedDescription)
        }
    }
}
