import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
import JapaneseLearningCardCore

struct VisibleCardTimerState: Equatable {
    var duration: TimeInterval
    var deadline: Date?
    var pausedRemainingSeconds: TimeInterval?

    var isActive: Bool {
        deadline != nil || pausedRemainingSeconds != nil
    }

    func remainingFraction(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        let remaining = if let deadline {
            max(0, deadline.timeIntervalSince(date))
        } else {
            max(0, pausedRemainingSeconds ?? duration)
        }
        return min(1, max(0, remaining / duration))
    }
}

struct QuickReviewSessionState: Equatable {
    var duration: TimeInterval
    var endDate: Date?
    var pausedRemainingSeconds: TimeInterval?

    var isActive: Bool {
        endDate != nil || pausedRemainingSeconds != nil
    }

    func remainingSeconds(at date: Date = Date()) -> TimeInterval {
        if let endDate {
            return max(0, endDate.timeIntervalSince(date))
        }
        return max(0, pausedRemainingSeconds ?? duration)
    }
}

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
    /// 正在驗證連線的來源 id（含 new-URL 欄位使用的 sentinel）。
    @Published var validatingSourceIDs: Set<UUID> = []
    /// 各來源最近一次「驗證連線」的診斷結果。
    @Published var sourceDiagnostics: [UUID: SourceDiagnostic] = [:]
    /// 新增網址欄位驗證時使用的固定 id。
    static let newSourceDiagnosticID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
    @Published var statusMessage = ""
    @Published var isUserInteracting = false
    @Published private(set) var isPopoverVisible = false
    @Published var isGeneratingAIArticle = false
    @Published var isGeneratingManualCards = false
    @Published var manualCardInput = ""
    @Published var manualCardInstruction = ""
    @Published var aiArticleCustomTheme = ""
    @Published var selectedTab = 0
    @Published private(set) var visibleCardTimerState = VisibleCardTimerState(
        duration: 20,
        deadline: nil,
        pausedRemainingSeconds: nil
    )
    @Published private(set) var quickReviewSessionState = QuickReviewSessionState(
        duration: 180,
        endDate: nil,
        pausedRemainingSeconds: nil
    )
    @Published private(set) var isQuickReviewActive = false
    @Published var storageSettings: StorageSettings
    @Published private(set) var storageHealth: DataStoreHealth?
    @Published private(set) var isMigratingStorage = false
    @Published private(set) var isBackfillingCards = false
    /// iOS only: set by exportDatabase() so the UI can present a share sheet.
    @Published var exportedDatabaseURL: URL?

    /// 簡報模式：手動開關。開著時暫停卡片自動彈出，直到使用者自己關掉
    /// （持久化，重開 App 也記得）。
    @Published var presentationModeEnabled = UserDefaults.standard.bool(forKey: AppViewModel.presentationModeKey) {
        didSet { UserDefaults.standard.set(presentationModeEnabled, forKey: Self.presentationModeKey) }
    }
    /// 自動偵測到的簡報情境（接投影機鏡像 / 全螢幕播放），由 PresentationDetector 更新。
    @Published private(set) var presentationAutoDetected = false

    static let presentationModeKey = "presentationModeEnabled"

    #if os(macOS)
    private let presentationDetector = PresentationDetector()
    #endif
    /// 開著就一直暫停，直到自己按繼續。
    @Published var autoDisplayPaused = UserDefaults.standard.bool(forKey: AppViewModel.autoDisplayPausedKey) {
        didSet { UserDefaults.standard.set(autoDisplayPaused, forKey: Self.autoDisplayPausedKey) }
    }
    static let autoDisplayPausedKey = "autoDisplayPaused"

    /// 簡報情境是否暫停中：手動簡報開關或自動偵測任一成立（給簡報按鈕顯示用）。
    var isPresentationPaused: Bool { presentationModeEnabled || presentationAutoDetected }

    /// 目前是否該暫停自動彈出：手動暫停或簡報情境任一成立（自動彈出的總閘門）。
    var isAutoDisplaySuppressed: Bool { autoDisplayPaused || isPresentationPaused }

    // iCloud 同步狀態 (給 settings 頁詳細面板用)
    @Published private(set) var iCloudStatus: CloudKitAccountChecker.Result = .unknown(underlying: "尚未檢查")
    @Published private(set) var iCloudFingerprint: String?
    @Published private(set) var iCloudLastPushAt: Date?
    @Published private(set) var iCloudLastPullAt: Date?
    @Published private(set) var iCloudConflicts: [ConflictRecord] = []
    @Published private(set) var iCloudLastErrorMessage: String?
    @Published private(set) var iCloudIsSyncing: Bool = false

    /// 未解衝突數 (isResolved == false 的), 給 settings 紅點用
    var iCloudConflictCount: Int {
        iCloudConflicts.filter { !$0.isResolved }.count
    }

    var isICloudSyncAvailable: Bool {
        #if ICLOUD_ENABLED && !LOCAL_BUILD
        return storageSettings.mode == .cloudKit && syncCoordinator != nil
        #else
        return false
        #endif
    }

    private var store: AppStore
    private let secretStore: SecretStore
    private let providerClient: OpenAICompatibleLLMClient
    private let schedulerPolicy = SchedulerPolicy()
    private let cardSelector = CardSelector()
    private let connectionTester = SourceConnectionTester()
    private var pipeline: LearningPipeline
    private var displayTimer: Timer?
    private var crawlTimer: Timer?
    private var aiArticleTimer: Timer?
    private var autoCloseTask: Task<Void, Never>?
    private var autoCloseGeneration = 0
    private var autoCloseRemainingSeconds: TimeInterval? {
        didSet { updateVisibleCardTimerState() }
    }
    private var autoCloseDeadline: Date? {
        didSet { updateVisibleCardTimerState() }
    }
    private var quickReviewTask: Task<Void, Never>?
    private var quickReviewGeneration = 0
    private var quickReviewSessionRemainingSeconds: TimeInterval? {
        didSet { updateQuickReviewSessionState() }
    }
    private var quickReviewSessionEndDate: Date? {
        didSet { updateQuickReviewSessionState() }
    }
    private var quickReviewCardRemainingSeconds: TimeInterval? {
        didSet { updateVisibleCardTimerState() }
    }
    private var quickReviewCardDeadline: Date? {
        didSet { updateVisibleCardTimerState() }
    }
    #if os(macOS)
    nonisolated(unsafe) private var sleepWakeObservers: [NSObjectProtocol] = []
    #endif
    private var isSuspended = false
    private let accountChecker = CloudKitAccountChecker()
    private let conflictStore = ConflictStore(storeURL: ConflictStore.defaultURL())
    private let syncedBase = SyncedBaseStore(url: SyncedBaseStore.defaultURL())
    private var syncCoordinator: SyncCoordinator?
    private var syncPollTimer: Timer?
    private var pushDebounceTask: Task<Void, Never>?
    private var lastSnapshotDataVersion: Int64?
    var requestShowPopover: (() -> Void)?
    var requestClosePopover: (() -> Void)?
    /// 使用者按「立即檢查更新」時呼叫，由 AppDelegate 接到 Sparkle。
    var requestCheckForUpdates: (() -> Void)?
    /// 「自動檢查更新」開關變動時呼叫，橋接到 Sparkle 的排程檢查。
    var setAutomaticUpdateChecks: ((Bool) -> Void)?

    init(store: AppStore, secretStore: SecretStore = KeychainStore(), storageSettings: StorageSettings = StorageSettingsStore.load()) {
        self.store = store
        self.secretStore = secretStore
        self.providerClient = OpenAICompatibleLLMClient(secretStore: secretStore)
        self.storageSettings = storageSettings
        self.pipeline = LearningPipeline(store: store, crawler: BrowserFallbackCrawler(), llmClient: self.providerClient)
        registerSleepWakeObservers()
        attachExternalChangeHandler(to: store)
    }

    deinit {
        #if os(macOS)
        for observer in sleepWakeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        #endif
    }

    func start() {
        #if os(macOS)
        // 自動偵測簡報情境，偵測到就暫停自動彈出，結束後自動恢復。
        presentationDetector.onChange = { [weak self] presenting in
            self?.presentationAutoDetected = presenting
        }
        presentationDetector.start()
        #endif
        Task {
            await reload()
            await store.ensureAISentinelSource(extractionPrompt: AISource.sentinelExtractionPrompt)
            await reload()
            await updateStorageHealth()
            scheduleTimers()
            #if ICLOUD_ENABLED && !LOCAL_BUILD
            if storageSettings.mode == .cloudKit {
                await bootstrapICloudSync()
            } else {
                iCloudStatus = .unknown(underlying: "\(storageSettings.mode.displayName) 模式未啟用 CloudKit 同步")
            }
            #else
            // 沒有 iCloud entitlement 的 build (ad-hoc / swift run) 不啟動
            // CloudKit, 否則 CKContainer.__allocating_init 會被 amfi kill。
            // 給 UI 一個明確的狀態, 不要讓 iCloud 區塊永遠顯示「尚未檢查」。
            iCloudStatus = .unknown(underlying: "本地 / UI 驗證 build 已停用 iCloud 同步")
            #endif
        }
    }

    /// 開機時啟動 iCloud 同步流程: 檢查帳號、註冊訂閱、第一次 pull/push。
    /// 沒 iCloud entitlement 或帳號不可用時整段 no-op, app 退回純本地模式。
    /// 只在 build 時有 `ICLOUD_ENABLED` flag 才會編進 binary (build-app.sh
    /// 正式 Developer ID release 才會傳 `-D ICLOUD_ENABLED`；`LOCAL_BUILD`
    /// 一律停用同步。
    private func bootstrapICloudSync() async {
        #if ICLOUD_ENABLED && !LOCAL_BUILD
        let info = await accountChecker.info()
        iCloudStatus = info.status
        iCloudFingerprint = CloudKitAccountChecker.displayFingerprint(info.userRecordName)
        guard case .available = info.status else {
            print("iCloud not available: \(info.status)")
            return
        }

        let transport = CloudKitTransport(backing: CKContainerBacking())
        self.syncCoordinator = SyncCoordinator(
            transport: transport,
            store: store,
            syncedBase: syncedBase,
            conflictStore: conflictStore
        )

        // 註冊 silent push 訂閱 (失敗也不影響 pull, log 一下)
        do {
            try await transport.ensureSubscriptionRegistered()
        } catch {
            print("subscription registration failed: \(error)")
        }

        // 啟動定期 pull
        scheduleSyncPollTimer()

        // 第一次 pull (雲端有就 merge, 沒就 push 上去)
        await performSync()
        #endif
    }

    /// snapshot 變化時觸發 push。debounce 500ms 避免短時間多次寫入。
    private func schedulePushDebounced() {
        guard storageSettings.mode == .cloudKit else { return }
        pushDebounceTask?.cancel()
        pushDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSync(direction: .push)
        }
    }

    /// 從雲端拉一次 (前景 / 定時 / 啟動都會叫)。
    func performPull() async {
        guard storageSettings.mode == .cloudKit else { return }
        #if LOCAL_BUILD
        return
        #else
        await performSync(direction: .pull)
        #endif
    }

    private enum SyncDirection { case push, pull, both }

    private func performSync(direction: SyncDirection = .both) async {
        guard let syncCoordinator else { return }
        iCloudIsSyncing = true
        defer { iCloudIsSyncing = false }
        iCloudLastErrorMessage = nil
        do {
            if direction == .pull || direction == .both {
                do {
                    try await syncCoordinator.pullAndMerge()
                    iCloudLastPullAt = Date()
                    iCloudConflicts = await conflictStore.records
                    await reload()
                } catch SyncCoordinator.SyncError.pullFailed(let msg) {
                    print("pull failed: \(msg)")
                }
            }
            if direction == .push || direction == .both {
                try await syncCoordinator.pushIfNeeded()
                iCloudLastPushAt = Date()
            }
        } catch {
            iCloudLastErrorMessage = String(describing: error)
            print("sync failed: \(error)")
        }
    }

    /// User 在 UI 上手動選了「用 local / remote」解某個衝突:
    /// 1. 把選中的 record 套回 local store (overwrite LWW 結果)
    /// 2. 把 conflict 標記為 resolved
    /// 3. 推一次讓雲端同步
    func resolveConflict(_ conflictId: UUID, useLocal: Bool) async {
        guard let conflict = iCloudConflicts.first(where: { $0.id == conflictId }) else { return }
        let chosenData = useLocal ? conflict.localValue : conflict.remoteValue
        let chosenResolution: ConflictRecord.Resolution = useLocal ? .tookLocal : .tookRemote

        // 把選中的 record decode 回對應型別, 寫進 local store
        do {
            try await applyConflictResolution(table: conflict.table, recordId: conflict.recordId, data: chosenData)
        } catch {
            iCloudLastErrorMessage = "套用衝突解決失敗: \(error)"
            print("resolveConflict apply failed: \(error)")
            return
        }

        await conflictStore.updateResolution(conflictId, to: chosenResolution)
        iCloudConflicts = await conflictStore.records
        await reload()

        // 推一次讓雲端知道
        do {
            try await syncCoordinator?.pushIfNeeded()
        } catch {
            iCloudLastErrorMessage = "推送衝突解決失敗: \(error)"
        }
    }

    /// 從衝突的 JSON blob decode 出對應 record 寫進 store。
    private func applyConflictResolution(table: ConflictRecord.Table, recordId: String, data: Data) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 先把 decode 做完 (throws) 再進 update closure (不 throws)
        let newSettings: AppSettings? = (table == .settings) ? try decoder.decode(AppSettings.self, from: data) : nil
        let newSource: Source? = (table == .sources) ? try decoder.decode(Source.self, from: data) : nil
        let newDoc: CrawledDocument? = (table == .crawledDocuments) ? try decoder.decode(CrawledDocument.self, from: data) : nil
        let newCard: LearningCard? = (table == .learningCards) ? try decoder.decode(LearningCard.self, from: data) : nil
        let newQuiz: QuizQuestion? = (table == .quizQuestions) ? try decoder.decode(QuizQuestion.self, from: data) : nil
        let newArticle: GeneratedArticle? = (table == .generatedArticles) ? try decoder.decode(GeneratedArticle.self, from: data) : nil

        try await store.update { state in
            switch table {
            case .settings:
                if let v = newSettings { state.settings = v }
            case .sources:
                if let v = newSource { Self.replaceOrAppend(&state.sources, id: recordId, value: v) }
            case .crawledDocuments:
                if let v = newDoc { Self.replaceOrAppendByKey(&state.documents, key: { $0.contentHash }, recordId: recordId, value: v) }
            case .learningCards:
                if let v = newCard { Self.replaceOrAppend(&state.cards, id: recordId, value: v) }
            case .quizQuestions:
                if let v = newQuiz { Self.replaceOrAppend(&state.quizzes, id: recordId, value: v) }
            case .generatedArticles:
                if let v = newArticle { Self.replaceOrAppend(&state.generatedArticles, id: recordId, value: v) }
            }
        }
    }

    nonisolated private static func replaceOrAppend<T: Identifiable>(_ list: inout [T], id: String, value: T) where T.ID == UUID {
        guard let uuid = UUID(uuidString: id) else { return }
        if let idx = list.firstIndex(where: { $0.id == uuid }) {
            list[idx] = value
        } else {
            list.append(value)
        }
    }

    nonisolated private static func replaceOrAppendByKey<T>(
        _ list: inout [T],
        key: (T) -> String,
        recordId: String,
        value: T
    ) {
        if let idx = list.firstIndex(where: { key($0) == recordId }) {
            list[idx] = value
        } else {
            list.append(value)
        }
    }

    private func scheduleSyncPollTimer() {
        syncPollTimer?.invalidate()
        // macOS push 不可靠, 每 60 秒主動 pull 一次當保底
        syncPollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performPull()
            }
        }
    }

    func reload() async {
        snapshot = await store.read()
        updateVisibleCardTimerState()
        aiArticleCustomTheme = snapshot.settings.aiArticleCustomTheme
        if let currentCard,
           let updatedCard = snapshot.cards.first(where: { $0.id == currentCard.id }),
           updatedCard.status != .skipped,
           updatedCard.status != .learned {
            self.currentCard = updatedCard
        } else {
            currentCard = cardSelector.nextCard(from: snapshot.cards)
        }
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
        // 任何 reload (來自本地寫入或 pull 後 merge) 都排一個 debounce push,
        // 避免快照改了卻忘記上雲。
        schedulePushDebounced()
    }

    func chooseICloudDriveFolderAndMigrate() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "選擇 iCloud Drive 資料夾"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = UserDataStoreFactory.defaultICloudDriveFolder().deletingLastPathComponent()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        switchStorageMode(.iCloudDriveFolder, folder: folder)
        #else
        // iOS: UIDocumentPickerViewController could be used here, but for simplicity
        // we switch directly to the default iCloud Drive folder.  A folder picker
        // can be added in a future iteration.
        switchStorageMode(.iCloudDriveFolder, folder: UserDataStoreFactory.defaultICloudDriveFolder())
        #endif
    }

    func switchStorageMode(_ mode: StorageMode, folder: URL? = nil) {
        guard !isMigratingStorage else { return }
        isMigratingStorage = true
        statusMessage = "資料遷移中..."
        let currentSettings = storageSettings
        Task {
            do {
                let currentSnapshot = await store.read()
                var nextSettings = currentSettings
                nextSettings.mode = mode
                switch mode {
                case .localOnly:
                    nextSettings.localDataPath = UserDataStoreFactory.defaultLocalFolder().path
                case .iCloudDriveFolder:
                    let selected = folder ?? UserDataStoreFactory.defaultICloudDriveFolder()
                    nextSettings.iCloudDriveFolderPath = selected.path
                case .cloudKit:
                    break
                }

                let nextStoreURL = UserDataStoreFactory.databaseURL(for: nextSettings)
                try FileManager.default.createDirectory(at: nextStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let nextStore = await AppStore(fileURL: nextStoreURL)
                try await nextStore.replaceSnapshot(currentSnapshot)
                let verified = await nextStore.read()
                guard verified.cards.count == currentSnapshot.cards.count,
                      verified.sources.count == currentSnapshot.sources.count,
                      verified.documents.count == currentSnapshot.documents.count else {
                    throw NSError(domain: "JapaneseLearningCard.StorageMigration", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "遷移驗證失敗：目標資料筆數不一致"
                    ])
                }

                await MainActor.run {
                    self.applyActiveStore(nextStore, settings: nextSettings)
                    StorageSettingsStore.save(nextSettings)
                    self.isMigratingStorage = false
                    self.statusMessage = "已切換到 \(mode.displayName)"
                }
                await updateStorageHealth()
                await reload()
            } catch {
                await MainActor.run {
                    self.isMigratingStorage = false
                    self.statusMessage = "資料遷移失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    func backfillExistingCards() {
        guard !isBackfillingCards else { return }
        isBackfillingCards = true
        statusMessage = "批次重生既有卡片中..."
        Task {
            let outcome = await pipeline.backfillExistingCards(limitToIncompleteCards: true)
            await MainActor.run {
                self.isBackfillingCards = false
                if outcome.failures.isEmpty {
                    self.statusMessage = "已補齊 \(outcome.updatedCards) 張卡片，處理 \(outcome.processedDocuments) 份文件"
                } else {
                    self.statusMessage = "已補齊 \(outcome.updatedCards) 張卡片，失敗 \(outcome.failures.count) 份"
                }
            }
            await reload()
        }
    }

    func showNextCard() {
        let isAutoShow = !isPopoverVisible
        // 暫停（手動暫停 / 簡報模式）只擋「自動彈出」，不影響使用者手動切下一張。
        // 直接 return，不更新 lastShownAt / shownCount，避免把沒看到的卡算成看過。
        if isAutoShow && isAutoDisplaySuppressed { return }
        if isAutoShow {
            selectedTab = 0
        }
        guard let selectedCard = cardSelector.nextCard(from: snapshot.cards) else {
            currentCard = nil
            if isAutoShow {
                requestShowPopover?()
            }
            return
        }

        Task {
            try? await store.update { state in
                if let index = state.cards.firstIndex(where: { $0.id == selectedCard.id }) {
                    state.cards[index].lastShownAt = Date()
                    state.cards[index].shownCount += 1
                    if state.cards[index].status == .new {
                        state.cards[index].status = .reviewing
                    }
                }
            }
            let updatedSnapshot = await store.read()
            await MainActor.run {
                snapshot = updatedSnapshot
                currentCard = updatedSnapshot.cards.first { $0.id == selectedCard.id } ?? selectedCard
                schedulePushDebounced()
            }
            if isAutoShow {
                requestShowPopover?()
            }
            if isQuickReviewActive {
                resetQuickReviewCardTimerForNewCard()
            } else {
                resetAutoCloseForNewCard()
            }
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

    @discardableResult
    func addSource(_ rawURL: String? = nil) -> Bool {
        let sourceURL = rawURL ?? newSourceURL
        guard let url = URL(string: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "網址格式不正確"
            return false
        }

        do {
            try SourceValidator().validate(url)
            storeUpdate { state in
                if !state.sources.contains(where: { $0.url == url }) {
                    state.sources.append(Source(url: url, extractionPrompt: state.settings.defaultExtractionPrompt))
                }
            }
            newSourceURL = ""
            sourceDiagnostics[Self.newSourceDiagnosticID] = nil
            statusMessage = "已新增來源"
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
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

    /// 驗證既有來源的連線狀態，並把結果寫回 `Source.lastError`（可連則清空）。
    func validateSource(_ source: Source) {
        guard !validatingSourceIDs.contains(source.id) else { return }
        validatingSourceIDs.insert(source.id)
        statusMessage = "驗證來源連線..."
        let url = source.url
        let id = source.id
        Task {
            let diagnostic = await connectionTester.test(url: url)
            await MainActor.run {
                self.sourceDiagnostics[id] = diagnostic
                self.validatingSourceIDs.remove(id)
                self.statusMessage = diagnostic.summary
                self.storeUpdate { state in
                    if let index = state.sources.firstIndex(where: { $0.id == id }) {
                        state.sources[index].lastError = diagnostic.errorMessageForSource
                    }
                }
            }
        }
    }

    /// 驗證「新增網址」欄位目前輸入的網址連線狀態（尚未加入清單時使用）。
    func validateNewSourceURL() {
        let trimmed = newSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = Self.newSourceDiagnosticID
        guard let url = URL(string: trimmed) else {
            sourceDiagnostics[id] = SourceDiagnostic(
                outcome: .invalidURL,
                summary: "網址格式不正確。",
                suggestion: "請確認網址完整且以 http:// 或 https:// 開頭。"
            )
            return
        }
        guard !validatingSourceIDs.contains(id) else { return }
        validatingSourceIDs.insert(id)
        statusMessage = "驗證來源連線..."
        Task {
            let diagnostic = await connectionTester.test(url: url)
            await MainActor.run {
                self.sourceDiagnostics[id] = diagnostic
                self.validatingSourceIDs.remove(id)
                self.statusMessage = diagnostic.summary
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
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        statusMessage = "已複製文章到剪貼簿"
    }

    func quitApp() {
        displayTimer?.invalidate()
        crawlTimer?.invalidate()
        aiArticleTimer?.invalidate()
        autoCloseTask?.cancel()
        requestClosePopover?()
        #if os(macOS)
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
        #endif
    }

    func exportDatabase() {
        Task {
            let sourceURL = await store.exportableDatabaseURL()
            #if os(macOS)
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
            #else
            // iOS: expose the URL so the UI layer can present a share sheet.
            await MainActor.run {
                self.exportedDatabaseURL = sourceURL
            }
            #endif
        }
    }

    func openAIRequestLog() {
        Task {
            do {
                let logURL = try await AIRequestLogStore.shared.ensureLogFile()
                await MainActor.run {
                    #if os(macOS)
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                    self.statusMessage = "已在 Finder 顯示 AI log：\(logURL.lastPathComponent)"
                    #else
                    self.statusMessage = "AI Log 路徑：\(logURL.path)"
                    #endif
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
        guard !isQuickReviewActive else { return }
        let duration = autoCloseRemainingSeconds ?? schedulerPolicy.visibleDuration(settings: snapshot.settings)
        scheduleAutoClose(after: duration)
    }

    func startQuickReview() {
        guard !snapshot.cards.filter({ $0.status != .skipped && $0.status != .learned }).isEmpty else {
            statusMessage = "目前沒有可複習的卡片"
            return
        }

        selectedTab = 0
        isQuickReviewActive = true
        statusMessage = "快速複習中"
        autoCloseTask?.cancel()
        autoCloseGeneration += 1
        autoCloseDeadline = nil
        autoCloseRemainingSeconds = nil

        let sessionDuration = TimeInterval(max(1, snapshot.settings.quickReviewDurationMinutes) * 60)
        let cardDuration = TimeInterval(max(5, snapshot.settings.quickReviewCardIntervalSeconds))
        quickReviewTask?.cancel()
        quickReviewGeneration += 1
        quickReviewSessionEndDate = nil
        quickReviewSessionRemainingSeconds = sessionDuration
        quickReviewCardDeadline = nil
        quickReviewCardRemainingSeconds = cardDuration

        if currentCard == nil {
            showNextCard()
        } else if !isUserInteracting {
            resumeQuickReviewTimers()
        }
    }

    func stopQuickReview() {
        finishQuickReview(message: "快速複習已結束")
    }

    private func resetAutoCloseForNewCard() {
        guard isPopoverVisible else { return }
        let duration = schedulerPolicy.visibleDuration(settings: snapshot.settings)
        autoCloseTask?.cancel()
        autoCloseGeneration += 1
        autoCloseDeadline = nil
        autoCloseRemainingSeconds = duration
        if !isUserInteracting {
            scheduleAutoClose(after: duration)
        }
    }

    private func resetQuickReviewCardTimerForNewCard() {
        guard isQuickReviewActive else { return }
        quickReviewTask?.cancel()
        quickReviewGeneration += 1
        quickReviewCardDeadline = nil
        quickReviewCardRemainingSeconds = TimeInterval(max(5, snapshot.settings.quickReviewCardIntervalSeconds))
        if !isUserInteracting {
            resumeQuickReviewTimers()
        }
    }

    private func resumeQuickReviewTimers() {
        guard isQuickReviewActive else { return }
        let now = Date()
        let sessionRemaining = quickReviewSessionRemainingSeconds
            ?? quickReviewSessionEndDate.map { max(0, $0.timeIntervalSince(now)) }
            ?? TimeInterval(max(1, snapshot.settings.quickReviewDurationMinutes) * 60)
        guard sessionRemaining > 0 else {
            finishQuickReview(message: "快速複習時間到")
            return
        }

        let cardRemaining = quickReviewCardRemainingSeconds
            ?? quickReviewCardDeadline.map { max(0, $0.timeIntervalSince(now)) }
            ?? TimeInterval(max(5, snapshot.settings.quickReviewCardIntervalSeconds))

        quickReviewSessionEndDate = now.addingTimeInterval(sessionRemaining)
        quickReviewSessionRemainingSeconds = sessionRemaining
        quickReviewCardDeadline = now.addingTimeInterval(cardRemaining)
        quickReviewCardRemainingSeconds = cardRemaining
        scheduleQuickReviewTask(after: min(sessionRemaining, cardRemaining))
    }

    private func pauseQuickReviewTimers() {
        guard isQuickReviewActive else { return }
        let now = Date()
        if let quickReviewSessionEndDate {
            quickReviewSessionRemainingSeconds = max(0.1, quickReviewSessionEndDate.timeIntervalSince(now))
        }
        if let quickReviewCardDeadline {
            quickReviewCardRemainingSeconds = max(0.1, quickReviewCardDeadline.timeIntervalSince(now))
        }
        quickReviewTask?.cancel()
        quickReviewGeneration += 1
        quickReviewSessionEndDate = nil
        quickReviewCardDeadline = nil
    }

    private func scheduleQuickReviewTask(after duration: TimeInterval) {
        quickReviewTask?.cancel()
        quickReviewGeneration += 1
        let generation = quickReviewGeneration
        quickReviewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            await MainActor.run {
                guard let self,
                      generation == self.quickReviewGeneration,
                      self.isQuickReviewActive,
                      !self.isUserInteracting
                else { return }

                let now = Date()
                if let endDate = self.quickReviewSessionEndDate, endDate <= now {
                    self.finishQuickReview(message: "快速複習時間到")
                    return
                }

                if let deadline = self.quickReviewCardDeadline, deadline <= now {
                    self.showNextCard()
                } else {
                    self.resumeQuickReviewTimers()
                }
            }
        }
    }

    private func finishQuickReview(message: String) {
        isQuickReviewActive = false
        quickReviewTask?.cancel()
        quickReviewGeneration += 1
        quickReviewSessionEndDate = nil
        quickReviewSessionRemainingSeconds = nil
        quickReviewCardDeadline = nil
        quickReviewCardRemainingSeconds = nil
        statusMessage = message
    }

    private func scheduleAutoClose(after duration: TimeInterval) {
        guard isPopoverVisible else { return }
        guard !isQuickReviewActive else { return }
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

    private func updateVisibleCardTimerState() {
        if isQuickReviewActive {
            visibleCardTimerState = VisibleCardTimerState(
                duration: TimeInterval(max(5, snapshot.settings.quickReviewCardIntervalSeconds)),
                deadline: quickReviewCardDeadline,
                pausedRemainingSeconds: quickReviewCardDeadline == nil ? quickReviewCardRemainingSeconds : nil
            )
            return
        }

        visibleCardTimerState = VisibleCardTimerState(
            duration: schedulerPolicy.visibleDuration(settings: snapshot.settings),
            deadline: autoCloseDeadline,
            pausedRemainingSeconds: autoCloseDeadline == nil ? autoCloseRemainingSeconds : nil
        )
    }

    private func updateQuickReviewSessionState() {
        quickReviewSessionState = QuickReviewSessionState(
            duration: TimeInterval(max(1, snapshot.settings.quickReviewDurationMinutes) * 60),
            endDate: quickReviewSessionEndDate,
            pausedRemainingSeconds: quickReviewSessionEndDate == nil ? quickReviewSessionRemainingSeconds : nil
        )
    }

    func pauseAutoCloseForInteraction() {
        guard !isUserInteracting else { return }
        isUserInteracting = true
        pauseQuickReviewTimers()
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
        resumeQuickReviewTimers()
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
        finishQuickReview(message: "")
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
        #if os(macOS)
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
        #endif
        // iOS: the OS suspends the process on sleep; no observers needed.
    }

    private func pauseTimers() {
        guard !isSuspended else { return }
        isSuspended = true
        finishQuickReview(message: "")
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

    private func applyActiveStore(_ newStore: AppStore, settings: StorageSettings) {
        syncCoordinator = nil
        pushDebounceTask?.cancel()
        syncPollTimer?.invalidate()
        syncPollTimer = nil
        store = newStore
        storageSettings = settings
        pipeline = LearningPipeline(store: newStore, crawler: BrowserFallbackCrawler(), llmClient: providerClient)
        attachExternalChangeHandler(to: newStore)
        #if ICLOUD_ENABLED && !LOCAL_BUILD
        if settings.mode == .cloudKit {
            Task { await bootstrapICloudSync() }
        } else {
            iCloudStatus = .unknown(underlying: "\(settings.mode.displayName) 模式未啟用 CloudKit 同步")
            iCloudFingerprint = nil
            iCloudLastErrorMessage = nil
            iCloudIsSyncing = false
        }
        #endif
    }

    private func attachExternalChangeHandler(to store: AppStore) {
        let onChange: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in await self?.reload() }
        }
        Task { await store.setOnExternalChange(onChange) }
    }

    private func updateStorageHealth() async {
        let url = await store.exportableDatabaseURL()
        let dataStore = SQLiteUserDataStore(store: store, location: url)
        let health = try? await dataStore.getHealth()
        await MainActor.run {
            self.storageHealth = health
        }
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
