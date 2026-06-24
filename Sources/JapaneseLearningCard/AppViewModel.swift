import Combine
import AppKit
import Foundation
import JapaneseLearningCardCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var snapshot = AppSnapshot()
    @Published var currentCard: LearningCard?
    @Published var currentQuiz: QuizQuestion?
    @Published var selectedQuizAnswer = ""
    @Published var isGeneratingQuiz = false
    @Published var isGeneratingExampleReading = false
    @Published var isRefreshing = false
    @Published var apiKeyInput = ""
    @Published var availableModels: [String] = ProviderPreset.openAI.fallbackModels
    @Published var isValidatingProvider = false
    @Published var newSourceURL = ""
    @Published var statusMessage = ""
    @Published var isUserInteracting = false
    @Published private(set) var isPopoverVisible = false
    @Published var isGeneratingAIArticle = false
    @Published var isGeneratingManualCards = false
    @Published var manualCardInput = ""
    @Published var manualCardInstruction = ""
    @Published var aiArticleCustomTheme = ""
    @Published var selectedTab = 0

    private let store: AppStore
    private let secretStore: SecretStore
    private let providerClient: OpenAICompatibleLLMClient
    private let schedulerPolicy = SchedulerPolicy()
    private let cardSelector = CardSelector()
    private lazy var pipeline = LearningPipeline(store: store, crawler: BrowserFallbackCrawler())
    private var displayTimer: Timer?
    private var crawlTimer: Timer?
    private var aiArticleTimer: Timer?
    private var autoCloseTask: Task<Void, Never>?
    private var autoCloseGeneration = 0
    private var autoCloseRemainingSeconds: TimeInterval?
    private var autoCloseDeadline: Date?
    nonisolated(unsafe) private var sleepWakeObservers: [NSObjectProtocol] = []
    private var isSuspended = false
    var requestShowPopover: (() -> Void)?
    var requestClosePopover: (() -> Void)?

    init(store: AppStore, secretStore: SecretStore = KeychainStore()) {
        self.store = store
        self.secretStore = secretStore
        self.providerClient = OpenAICompatibleLLMClient(secretStore: secretStore)
        registerSleepWakeObservers()
    }

    deinit {
        for observer in sleepWakeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func start() {
        Task {
            await reload()
            await store.ensureAISentinelSource(extractionPrompt: AISource.sentinelExtractionPrompt)
            await reload()
            scheduleTimers()
        }
    }

    func reload() async {
        snapshot = await store.read()
        aiArticleCustomTheme = snapshot.settings.aiArticleCustomTheme
        currentCard = cardSelector.nextCard(from: snapshot.cards)
        if let existingQuiz = currentQuiz,
           let updatedQuiz = snapshot.quizzes.first(where: { $0.id == existingQuiz.id }),
           updatedQuiz.status != .pending {
            currentQuiz = updatedQuiz
        } else {
            currentQuiz = snapshot.quizzes
                .filter { $0.status == .pending }
                .sorted { $0.createdAt < $1.createdAt }
                .first
        }
        if availableModels.isEmpty || !availableModels.contains(snapshot.settings.providerConfig.model) {
            availableModels = Array(Set(snapshot.settings.providerConfig.preset.fallbackModels + [snapshot.settings.providerConfig.model])).sorted()
        }
    }

    func showNextCard() {
        currentCard = cardSelector.nextCard(from: snapshot.cards)
        let isAutoShow = !isPopoverVisible
        if isAutoShow {
            selectedTab = 0
        }
        guard let card = currentCard else {
            if isAutoShow {
                requestShowPopover?()
            }
            return
        }

        Task {
            try? await store.update { state in
                if let index = state.cards.firstIndex(where: { $0.id == card.id }) {
                    state.cards[index].lastShownAt = Date()
                    if state.cards[index].status == .new {
                        state.cards[index].status = .reviewing
                    }
                }
            }
            await reload()
            if isAutoShow {
                requestShowPopover?()
            }
            scheduleAutoClose()
        }
    }

    func refreshNow() {
        isRefreshing = true
        statusMessage = "更新中..."
        Task {
            await pipeline.refreshEnabledSources()
            await reload()
            isRefreshing = false
            statusMessage = "已更新"
        }
    }

    func generateAIArticleNow(theme: String? = nil) {
        guard !isGeneratingAIArticle else { return }
        isGeneratingAIArticle = true
        statusMessage = "AI 生成文章中..."
        Task {
            let result = await pipeline.generateAIArticleNow(theme: theme ?? aiArticleCustomTheme)
            await MainActor.run {
                self.isGeneratingAIArticle = false
                switch result {
                case .generated(let article):
                    self.statusMessage = "已產生「\(article.title)」(\(article.cardCount) 張卡)"
                case .duplicate:
                    self.statusMessage = "內容與既有文章重複，未新增"
                case .failed(let message):
                    self.statusMessage = "AI 文章產生失敗：\(message)"
                }
            }
            await reload()
        }
    }

    var canGenerateManualCards: Bool {
        !manualCardInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func generateManualCards() {
        guard !isGeneratingManualCards, canGenerateManualCards else { return }
        isGeneratingManualCards = true
        statusMessage = "AI 解析中，產生單字卡..."
        let text = manualCardInput
        let instruction = manualCardInstruction
        Task {
            let result = await pipeline.generateCardsFromText(text, instruction: instruction)
            await MainActor.run {
                self.isGeneratingManualCards = false
                switch result {
                case .generated(let count):
                    self.statusMessage = "已從輸入內容產生 \(count) 張單字卡"
                    self.manualCardInput = ""
                    self.manualCardInstruction = ""
                case .empty:
                    self.statusMessage = "AI 沒有從內容中找到可用的單字"
                case .failed(let message):
                    self.statusMessage = "產生單字卡失敗：\(message)"
                }
            }
            await reload()
        }
    }

    func toggleAIArticleLevel(_ level: JLPTLevel) {
        var settings = snapshot.settings
        if settings.aiArticleLevels.contains(level) {
            settings.aiArticleLevels.removeAll { $0 == level }
        } else {
            settings.aiArticleLevels.append(level)
        }
        if settings.aiArticleLevels.isEmpty {
            settings.aiArticleLevels = JLPTLevel.allCases
        }
        updateSettings(settings)
    }

    func setAIArticleEnabled(_ enabled: Bool) {
        var settings = snapshot.settings
        settings.aiArticleEnabled = enabled
        updateSettings(settings)
    }

    func setAIArticleIntervalHours(_ hours: Int) {
        var settings = snapshot.settings
        settings.aiArticleIntervalHours = max(1, hours)
        updateSettings(settings)
    }

    func setAIArticleScheduleTime(hour: Int, minute: Int) {
        var settings = snapshot.settings
        settings.aiArticleScheduleHour = AppSettings.clampHour(hour)
        settings.aiArticleScheduleMinute = AppSettings.clampMinute(minute)
        updateSettings(settings)
    }

    func toggleAIArticleWeekday(_ weekday: Int) {
        var settings = snapshot.settings
        var weekdays = Set(settings.aiArticleWeekdays)
        if weekdays.contains(weekday) {
            weekdays.remove(weekday)
        } else {
            weekdays.insert(weekday)
        }
        settings.aiArticleWeekdays = AppSettings.normalizeWeekdays(Array(weekdays))
        updateSettings(settings)
    }

    func setAIArticleCustomTheme(_ theme: String) {
        aiArticleCustomTheme = theme
        var settings = snapshot.settings
        settings.aiArticleCustomTheme = theme
        updateSettings(settings)
    }

    func addSource() {
        guard let url = URL(string: newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "網址格式不正確"
            return
        }

        do {
            try SourceValidator().validate(url)
            storeUpdate { state in
                if !state.sources.contains(where: { $0.url == url }) {
                    state.sources.append(Source(url: url, extractionPrompt: state.settings.defaultExtractionPrompt))
                }
            }
            newSourceURL = ""
            statusMessage = "已新增來源"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func removeSource(_ source: Source) {
        storeUpdate { state in
            state.sources.removeAll { $0.id == source.id }
        }
    }

    /// 更新既有來源的網址；格式錯誤或重複時回傳 false 並設定 statusMessage。
    @discardableResult
    func updateSourceURL(_ source: Source, to rawURL: String) -> Bool {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != source.url.absoluteString else { return true }
        guard let url = URL(string: trimmed) else {
            statusMessage = "網址格式不正確"
            return false
        }
        do {
            try SourceValidator().validate(url)
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
        if snapshot.sources.contains(where: { $0.id != source.id && $0.url == url }) {
            statusMessage = "已有相同網址的來源"
            return false
        }
        storeUpdate { state in
            if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                state.sources[index].url = url
                state.sources[index].lastError = nil
            }
        }
        statusMessage = "已更新網址"
        return true
    }

    func toggleSource(_ source: Source) {
        storeUpdate { state in
            if let index = state.sources.firstIndex(where: { $0.id == source.id }) {
                state.sources[index].isEnabled.toggle()
            }
        }
    }

    func updateSettings(_ settings: AppSettings) {
        storeUpdate { state in
            state.settings = settings
        }
        scheduleTimers()
    }

    func validateAndSaveProvider() {
        isValidatingProvider = true
        statusMessage = "驗證 provider..."
        Task {
            do {
                let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                // 先用「輸入的 key」(若留空則用既有 key) 驗證，成功才寫入 Keychain；失敗不動 Keychain。
                let candidateKey: String?
                if trimmedKey.isEmpty {
                    let existingKey = try secretStore.apiKey(reference: snapshot.settings.providerConfig.apiKeyKeychainRef)
                    guard existingKey?.isEmpty == false else {
                        throw LLMClientError.missingAPIKey
                    }
                    candidateKey = nil
                } else {
                    candidateKey = trimmedKey
                }

                let models = try await providerClient.listModels(settings: snapshot.settings, apiKeyOverride: candidateKey)

                // 驗證成功後才儲存新的 key。
                if let candidateKey {
                    try secretStore.saveAPIKey(candidateKey, reference: snapshot.settings.providerConfig.apiKeyKeychainRef)
                }
                await MainActor.run {
                    self.availableModels = models.isEmpty ? self.snapshot.settings.providerConfig.preset.fallbackModels : models
                    if !self.availableModels.contains(self.snapshot.settings.providerConfig.model),
                       let firstModel = self.availableModels.first {
                        var settings = self.snapshot.settings
                        settings.providerConfig.model = firstModel
                        self.updateSettings(settings)
                    }
                    self.apiKeyInput = ""
                    self.isValidatingProvider = false
                    self.statusMessage = "Provider 驗證成功，已取得 \(self.availableModels.count) 個 model"
                }
            } catch {
                await MainActor.run {
                    self.isValidatingProvider = false
                    self.statusMessage = "驗證失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    func applyProviderPreset(_ preset: ProviderPreset) {
        var settings = snapshot.settings
        settings.providerConfig.preset = preset
        settings.providerConfig.baseURL = preset.defaultBaseURL
        settings.providerConfig.model = preset.defaultModel
        settings.providerConfig.apiKeyKeychainRef = preset.rawValue
        settings.providerConfig.structuredOutput = preset.defaultStructuredOutput
        availableModels = preset.fallbackModels
        updateSettings(settings)
    }

    func markCurrentCard(_ status: CardStatus) {
        guard let card = currentCard else { return }
        storeUpdate { state in
            if let index = state.cards.firstIndex(where: { $0.id == card.id }) {
                state.cards[index].status = status
            }
        }
    }

    func regenerateCurrentSource() {
        refreshNow()
    }

    func fillCurrentExampleReading() {
        guard let card = currentCard else { return }
        isGeneratingExampleReading = true
        statusMessage = "補平假名中..."
        Task {
            do {
                let reading = try await providerClient.generateExampleReading(exampleJa: card.exampleJa, settings: snapshot.settings)
                await MainActor.run {
                    guard !reading.isEmpty else {
                        self.isGeneratingExampleReading = false
                        self.statusMessage = "AI 沒有回傳平假名"
                        return
                    }
                    self.storeUpdate { state in
                        if let index = state.cards.firstIndex(where: { $0.id == card.id }) {
                            state.cards[index].exampleReading = reading
                        }
                    }
                    self.isGeneratingExampleReading = false
                    self.statusMessage = "已補上例句平假名"
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingExampleReading = false
                    self.statusMessage = "補平假名失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    func generateQuiz() {
        let cards = snapshot.cards.filter { $0.status != .skipped }
        guard !cards.isEmpty else {
            statusMessage = "目前沒有可用的學習卡，請先更新內容來源"
            return
        }

        isGeneratingQuiz = true
        statusMessage = "AI 出題中..."
        Task {
            do {
                let quizzes = try await providerClient.generateQuiz(cards: cards, settings: snapshot.settings)
                await MainActor.run {
                    guard !quizzes.isEmpty else {
                        self.isGeneratingQuiz = false
                        self.statusMessage = "AI 沒有產生有效考題"
                        return
                    }
                    self.storeUpdate { state in
                        state.quizzes.append(contentsOf: quizzes)
                    }
                    self.isGeneratingQuiz = false
                    self.statusMessage = "已產生 \(quizzes.count) 題"
                }
            } catch {
                await MainActor.run {
                    self.isGeneratingQuiz = false
                    self.statusMessage = "出題失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    func submitQuizAnswer(_ answer: String) {
        guard let quiz = currentQuiz else { return }
        selectedQuizAnswer = answer
        storeUpdate { state in
            if let index = state.quizzes.firstIndex(where: { $0.id == quiz.id }) {
                state.quizzes[index].selectedAnswer = answer
                state.quizzes[index].answeredAt = Date()
                state.quizzes[index].status = answer == state.quizzes[index].correctAnswer ? .correct : .incorrect
            }
        }
    }

    func skipCurrentQuiz() {
        guard let quiz = currentQuiz else { return }
        storeUpdate { state in
            if let index = state.quizzes.firstIndex(where: { $0.id == quiz.id }) {
                state.quizzes[index].status = .skipped
                state.quizzes[index].answeredAt = Date()
            }
        }
    }

    func showNextQuiz() {
        currentQuiz = nil
        Task { await reload() }
    }

    func copyArticle(_ article: GeneratedArticle) {
        let text = article.title.isEmpty ? article.plainText : "\(article.title)\n\n\(article.plainText)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "已複製文章到剪貼簿"
    }

    func quitApp() {
        displayTimer?.invalidate()
        crawlTimer?.invalidate()
        aiArticleTimer?.invalidate()
        autoCloseTask?.cancel()
        requestClosePopover?()
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    func exportDatabase() {
        Task {
            let sourceURL = await store.exportableDatabaseURL()
            await MainActor.run {
                let panel = NSSavePanel()
                panel.title = "匯出 SQLite 資料庫"
                panel.nameFieldStringValue = "JapaneseLearningCard-store.sqlite"
                panel.allowedContentTypes = [.database]
                panel.canCreateDirectories = true

                guard panel.runModal() == .OK, let destinationURL = panel.url else {
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    self.statusMessage = "已匯出 DB：\(destinationURL.lastPathComponent)"
                } catch {
                    self.statusMessage = "匯出失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    func openAIRequestLog() {
        Task {
            do {
                let logURL = try await AIRequestLogStore.shared.ensureLogFile()
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    self.statusMessage = "已在 Finder 顯示 AI log：\(logURL.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "開啟 AI log 失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    func scheduleAutoClose() {
        guard isPopoverVisible else { return }
        let duration = autoCloseRemainingSeconds ?? schedulerPolicy.visibleDuration(settings: snapshot.settings)
        scheduleAutoClose(after: duration)
    }

    private func scheduleAutoClose(after duration: TimeInterval) {
        guard isPopoverVisible else { return }
        guard duration > 0 else {
            requestClosePopover?()
            return
        }

        autoCloseTask?.cancel()
        autoCloseGeneration += 1
        let generation = autoCloseGeneration
        autoCloseDeadline = Date().addingTimeInterval(duration)
        autoCloseRemainingSeconds = duration
        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            await MainActor.run {
                guard let self,
                      generation == self.autoCloseGeneration,
                      self.isPopoverVisible,
                      !self.isUserInteracting else { return }
                self.autoCloseRemainingSeconds = nil
                self.autoCloseDeadline = nil
                self.requestClosePopover?()
            }
        }
    }

    func pauseAutoCloseForInteraction() {
        guard !isUserInteracting else { return }
        isUserInteracting = true
        if let deadline = autoCloseDeadline {
            autoCloseRemainingSeconds = max(0.1, deadline.timeIntervalSinceNow)
        } else if autoCloseRemainingSeconds == nil {
            autoCloseRemainingSeconds = schedulerPolicy.visibleDuration(settings: snapshot.settings)
        }
        autoCloseTask?.cancel()
        autoCloseGeneration += 1
        autoCloseDeadline = nil
    }

    func resumeAutoCloseAfterInteraction() {
        guard isUserInteracting else { return }
        isUserInteracting = false
        scheduleAutoClose()
    }

    func popoverDidShow(isMouseInside: Bool = false) {
        isPopoverVisible = true
        isUserInteracting = isMouseInside
        if isMouseInside {
            autoCloseRemainingSeconds = schedulerPolicy.visibleDuration(settings: snapshot.settings)
            autoCloseTask?.cancel()
            autoCloseGeneration += 1
            autoCloseDeadline = nil
        } else {
            autoCloseRemainingSeconds = schedulerPolicy.visibleDuration(settings: snapshot.settings)
            scheduleAutoClose()
        }
    }

    func popoverDidClose() {
        isPopoverVisible = false
        isUserInteracting = false
        autoCloseTask?.cancel()
        autoCloseGeneration += 1
        autoCloseRemainingSeconds = nil
        autoCloseDeadline = nil
    }

    private func scheduleTimers() {
        displayTimer?.invalidate()
        crawlTimer?.invalidate()
        aiArticleTimer?.invalidate()

        displayTimer = Timer.scheduledTimer(withTimeInterval: schedulerPolicy.displayInterval(settings: snapshot.settings), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.showNextCard() }
        }

        crawlTimer = Timer.scheduledTimer(withTimeInterval: schedulerPolicy.crawlInterval(settings: snapshot.settings), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }

        scheduleNextAIArticleTimer()
    }

    /// 依排程時間 / 星期幾安排下一次觸發。觸發後會自行重新排程下一輪。
    private func scheduleNextAIArticleTimer() {
        aiArticleTimer?.invalidate()
        aiArticleTimer = nil

        guard snapshot.settings.aiArticleEnabled else { return }
        guard let fireDate = schedulerPolicy.nextAIArticleFireDate(settings: snapshot.settings) else { return }

        let interval = max(1, fireDate.timeIntervalSinceNow)
        aiArticleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.generateAIArticleNow()
                self?.scheduleNextAIArticleTimer()
            }
        }
    }

    private func registerSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let entries: [(Notification.Name, Bool)] = [
            (NSWorkspace.willSleepNotification, true),
            (NSWorkspace.didWakeNotification, false),
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false)
        ]
        for (name, shouldPause) in entries {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    if shouldPause {
                        self?.pauseTimers()
                    } else {
                        self?.resumeTimers()
                    }
                }
            }
            sleepWakeObservers.append(observer)
        }
    }

    private func pauseTimers() {
        guard !isSuspended else { return }
        isSuspended = true
        displayTimer?.invalidate()
        crawlTimer?.invalidate()
        aiArticleTimer?.invalidate()
        autoCloseTask?.cancel()
        autoCloseGeneration += 1
        autoCloseDeadline = nil
        autoCloseRemainingSeconds = nil
        if isPopoverVisible {
            requestClosePopover?()
        }
    }

    private func resumeTimers() {
        guard isSuspended else { return }
        isSuspended = false
        scheduleTimers()
    }

    private func storeUpdate(_ mutate: @escaping @Sendable (inout AppSnapshot) -> Void) {
        Task {
            do {
                try await store.update(mutate)
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                }
            }
            await reload()
        }
    }
}
