import Foundation

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
}
