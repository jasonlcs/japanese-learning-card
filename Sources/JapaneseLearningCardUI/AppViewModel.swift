import Combine
import SwiftUI
import UniformTypeIdentifiers
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

enum ProviderKeyStatus: Equatable {
    case unknown
    case saved
    case missing
    case error(String)

    var displayText: String {
        switch self {
        case .unknown:
            "Key 狀態未知"
        case .saved:
            "Keychain 已儲存 API key"
        case .missing:
            "尚未儲存 API key"
        case .error(let message):
            "Keychain 檢查失敗：\(message)"
        }
    }
}

struct TTSVoiceOption: Identifiable, Equatable {
    var id: String
    var name: String

    var displayName: String {
        name.isEmpty || name == id ? id : "\(name) (\(id))"
    }
}

enum GeminiTTSOptions {
    static let models = [
        "gemini-3.1-flash-tts-preview",
        "gemini-2.5-flash-preview-tts",
        "gemini-2.5-pro-preview-tts"
    ]

    static let voices = [
        "Kore", "Puck", "Zephyr", "Charon", "Fenrir", "Leda", "Orus", "Aoede",
        "Callirrhoe", "Autonoe", "Enceladus", "Iapetus", "Umbriel", "Algieba",
        "Despina", "Erinome", "Algenib", "Rasalgethi", "Laomedeia", "Achernar",
        "Alnilam", "Schedar", "Gacrux", "Pulcherrima", "Achird", "Zubenelgenubi",
        "Vindemiatrix", "Sadachbia", "Sadaltager", "Sulafat"
    ]
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published var snapshot = AppSnapshot()
    @Published var currentCard: LearningCard?
    @Published var currentQuiz: QuizQuestion?
    @Published var selectedQuizAnswer = ""
    @Published var isGeneratingQuiz = false
    @Published var isGeneratingExampleReading = false
    @Published var isRefreshing = false
    @Published var apiKeyInput = ""
    @Published var openAITtsKeyInput = ""
    @Published var isOpenAITtsKeySaved = false
    @Published var availableModels: [String] = ProviderPreset.openAI.fallbackModels
    @Published var availableTtsModels: [String] = []
    @Published var availableTtsVoices: [TTSVoiceOption] = []
    @Published var isFetchingTtsModels = false
    @Published var ttsStatusMessage = ""
    @Published var isValidatingProvider = false
    @Published private(set) var activeProviderKeyStatus: ProviderKeyStatus = .unknown
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
    @Published public var selectedVocabularySource: VocabularySourceType = .all
    @Published public var userEssayPrompt = ""
    @Published public var previewVocabularyCards: [LearningCard] = []
    @Published public var isGeneratingEssay = false
    @Published public var essayGenerationProgress = ""
    @Published public var essayValidationError: String? = nil
    @Published public var lastGeneratedEssay: GeneratedArticle? = nil
    @Published public var exportedEssayURL: URL? = nil
    @Published public var essayGenerationError: String? = nil
    @Published public var isAnnotatingArticleRuby = false
    @Published public var essayCurrentStep: EssayGenerationStep? = nil
    private var essayGenerationTask: Task<Void, Never>?
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
    @Published private(set) var isQuickReviewActive = false {
        didSet { updateVisibleCardTimerState() }
    }
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
    /// 互動暫停時保留的最小剩餘秒數：避免在倒數快歸零時暫停，
    /// 進度條凍結在寬度 ≈ 0（看起來像消失），且恢復後瞬間關閉。
    private static let minimumPausedRemainingSeconds: TimeInterval = 3
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
    private var isRubyMigrationRunning = false
    private var lastSnapshotDataVersion: Int64?
    public var requestShowPopover: (() -> Void)?
    public var requestClosePopover: (() -> Void)?
    /// 自動關閉倒數到期時先問這個：popover 上還掛著 sheet 或使用者正在
    /// 輸入時回 true，改為重排倒數而不是把 popover 從使用者手上收掉。
    /// （onHover 偵測不到 sheet／鍵盤輸入，只靠它會在操作到一半關掉。）
    public var isPopoverBusy: (() -> Bool)?
    /// 使用者按「立即檢查更新」時呼叫，由 AppDelegate 接到 Sparkle。
    public var requestCheckForUpdates: (() -> Void)?
    /// 「自動檢查更新」開關變動時呼叫，橋接到 Sparkle 的排程檢查。
    public var setAutomaticUpdateChecks: ((Bool) -> Void)?

    public init(store: AppStore, secretStore: SecretStore = KeychainStore(), storageSettings: StorageSettings = StorageSettingsStore.load()) {
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

    public func start() {
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
            await migrateRubyOnceIfPossible()
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
    public func performPull() async {
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
        if snapshot.settings.providerProfiles.isEmpty || snapshot.settings.activeProviderProfile == nil {
            var settings = snapshot.settings
            settings.normalizeProviderProfiles()
            snapshot.settings = settings
            updateSettings(settings)
        }
        updateVisibleCardTimerState()
        aiArticleCustomTheme = snapshot.settings.aiArticleCustomTheme
        if previewVocabularyCards.isEmpty {
            shufflePreviewVocabulary()
        }
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
        if availableModels.isEmpty || !availableModels.contains(snapshot.settings.providerConfig.model) || !availableModels.contains(snapshot.settings.providerConfig.fastModel) {
            availableModels = Array(Set(snapshot.settings.providerConfig.preset.fallbackModels + [snapshot.settings.providerConfig.model, snapshot.settings.providerConfig.fastModel])).sorted()
        }
        migrateProviderKeychainReferencesIfNeeded()
        migrateTTSKeychainReferencesIfNeeded()
        refreshActiveProviderKeyStatus()
        // 任何 reload (來自本地寫入或 pull 後 merge) 都排一個 debounce push,
        // 避免快照改了卻忘記上雲。
        schedulePushDebounced()
    }

    private func migrateRubyOnceIfPossible() async {
        guard !isRubyMigrationRunning else { return }
        let current = await store.read()
        guard !current.settings.completedMigrations.contains(RubySupport.migrationId) else { return }
        guard current.cards.contains(where: \.needsRubyBackfill) else {
            _ = await pipeline.migrateRubyOnce()
            await reload()
            return
        }

        let keyReference = current.settings.providerConfig.apiKeyKeychainRef
        guard ((try? secretStore.apiKey(reference: keyReference)) ?? "").isEmpty == false else {
            statusMessage = "偵測到舊卡缺少 ruby；設定 API key 後會自動補齊一次"
            return
        }

        isRubyMigrationRunning = true
        statusMessage = "正在一次性補齊 ruby 讀音..."
        let outcome = await pipeline.migrateRubyOnce()
        isRubyMigrationRunning = false
        statusMessage = outcome.completed
            ? "已補齊 ruby：更新 \(outcome.updatedCards) 張卡"
            : "ruby 補齊未完成：\(outcome.failures.first ?? "未知錯誤")"
        await reload()
    }

    #if os(macOS)
    /// Menu bar app 的主視窗是 NSPopover，層級天生高於檔案面板（modal panel），
    /// 面板不抬高會被 popover 蓋住。這裡把面板抬到 popover 之上並搶焦點；
    /// 面板關閉後就消失，不影響 popover 原本的置頂行為。
    private func presentAbovePopover(_ panel: NSSavePanel) {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif

    func chooseICloudDriveFolderAndMigrate() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "選擇 iCloud Drive 資料夾"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = UserDataStoreFactory.defaultICloudDriveFolder().deletingLastPathComponent()
        presentAbovePopover(panel)
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

    public func refreshNow() {
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
        let id = source.id
        Task {
            var diagnostic = await connectionTester.test(url: source.url)
            // 連得到才接著實際呼叫 AI 解析；解析成功的卡片直接寫入 DB。
            if diagnostic.isReachable {
                await MainActor.run { self.statusMessage = "測試 AI 解析內容..." }
                diagnostic = await self.runAIParseTest(source: source, registerSource: false, into: diagnostic)
            }
            let finalDiagnostic = diagnostic
            await MainActor.run {
                self.sourceDiagnostics[id] = finalDiagnostic
                self.validatingSourceIDs.remove(id)
                self.statusMessage = finalDiagnostic.aiParseSummary ?? finalDiagnostic.summary
                self.storeUpdate { state in
                    if let index = state.sources.firstIndex(where: { $0.id == id }) {
                        state.sources[index].lastError = finalDiagnostic.errorMessageForSource
                    }
                }
            }
        }
    }

    /// 驗證「新增網址」欄位目前輸入的網址；解析成功會把來源與卡片一併加入 DB。
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
        // 與手動新增來源一致：帶上預設擷取 prompt。解析成功時會把這個來源登記進 DB。
        let newSource = Source(url: url, extractionPrompt: snapshot.settings.defaultExtractionPrompt)
        Task {
            var diagnostic = await connectionTester.test(url: url)
            if diagnostic.isReachable {
                await MainActor.run { self.statusMessage = "測試 AI 解析內容..." }
                diagnostic = await self.runAIParseTest(source: newSource, registerSource: true, into: diagnostic)
            }
            let finalDiagnostic = diagnostic
            // 解析未失敗代表來源已登記(stored 或 duplicate)：把診斷掛到新來源、清空輸入欄。
            let registered = finalDiagnostic.isReachable && finalDiagnostic.aiParseError == nil
            // pipeline 直接寫 store 不會觸發外部變更回呼，必須自行 reload 才會在清單看到新來源。
            if registered {
                await self.reload()
            }
            await MainActor.run {
                self.validatingSourceIDs.remove(id)
                self.statusMessage = finalDiagnostic.aiParseSummary ?? finalDiagnostic.summary
                if registered {
                    self.sourceDiagnostics[newSource.id] = finalDiagnostic
                    self.sourceDiagnostics[id] = nil
                    self.newSourceURL = ""
                } else {
                    self.sourceDiagnostics[id] = finalDiagnostic
                }
            }
        }
    }

    /// 實際抓取來源內容並呼叫 provider 解析；成功的卡片直接寫入 DB（contentHash 去重）。
    /// 只回報結果、不設成功門檻；`registerSource` 為 true 時(測試新網址)會一併登記來源。
    private func runAIParseTest(source: Source, registerSource: Bool, into diagnostic: SourceDiagnostic) async -> SourceDiagnostic {
        var result = diagnostic
        let outcome = await pipeline.parseAndStoreForValidation(source: source, registerSource: registerSource)
        switch outcome {
        case .stored(let cardCount):
            result.aiParsedCardCount = cardCount
            result.aiParseError = nil
            result.aiParseDuplicate = false
        case .duplicate:
            result.aiParsedCardCount = nil
            result.aiParseError = nil
            result.aiParseDuplicate = true
        case .failed(let message):
            result.aiParsedCardCount = nil
            result.aiParseError = message
            result.aiParseDuplicate = false
        }
        return result
    }

    func updateSettings(_ settings: AppSettings) {
        storeUpdate { state in
            state.settings = settings
        }
        scheduleTimers()
    }

    func setTTSMode(useAI: Bool) {
        var settings = snapshot.settings
        settings.openAITtsEnabled = useAI
        updateSettings(settings)
        statusMessage = useAI ? "已切換為 AI 發音" : "已切換為內建發音"
    }

    var activeProviderProfile: ProviderProfile? {
        snapshot.settings.activeProviderProfile
    }

    func selectProviderProfile(_ id: UUID) {
        var settings = snapshot.settings
        guard settings.providerProfiles.contains(where: { $0.id == id }) else { return }
        settings.activeProviderProfileId = id
        settings.normalizeProviderProfiles()
        applyProviderSettings(settings)
        availableModels = Array(Set(settings.providerConfig.preset.fallbackModels + [settings.providerConfig.model, settings.providerConfig.fastModel])).sorted()
        apiKeyInput = ""
    }

    /// keychain reference 新制:一律等於 profile id。舊資料(含 iCloud 同步
    /// 回來的 profile)在每次 reload 檢查一次,有不一致就把既有 key 搬到新
    /// reference,搬完才刪舊項目;失敗會留在舊 reference 等下次重試。
    private func migrateProviderKeychainReferencesIfNeeded() {
        guard let migrated = ProviderKeychainMigration.migrate(settings: snapshot.settings, secretStore: secretStore) else { return }
        applyProviderSettings(migrated)
    }

    func createProviderProfile() {
        var settings = snapshot.settings
        settings.normalizeProviderProfiles()
        let id = UUID()
        var config = ProviderConfig()
        config.apiKeyKeychainRef = ProviderProfile.keychainReference(for: id)
        let profile = ProviderProfile(id: id, name: "New \(config.preset.displayName)", config: config)
        settings.providerProfiles.append(profile)
        settings.activeProviderProfileId = profile.id
        settings.normalizeProviderProfiles()
        applyProviderSettings(settings)
        availableModels = config.preset.fallbackModels
        apiKeyInput = ""
    }

    func duplicateActiveProviderProfile() {
        var settings = snapshot.settings
        settings.normalizeProviderProfiles()
        guard let source = settings.activeProviderProfile else { return }
        var copy = source
        copy.id = UUID()
        copy.name = "\(source.name) Copy"
        copy.config.apiKeyKeychainRef = copy.keychainReference
        copy.lastVerifiedAt = nil
        copy.lastVerificationStatus = .missingKey
        copy.lastVerificationMessage = "複製 profile 後需要貼上 API key 並重新驗證。"
        copy.verifiedModelCount = nil
        copy.updatedAt = Date()
        settings.providerProfiles.append(copy)
        settings.activeProviderProfileId = copy.id
        settings.normalizeProviderProfiles()
        applyProviderSettings(settings)
        apiKeyInput = ""
    }

    func deleteActiveProviderProfile() {
        var settings = snapshot.settings
        settings.normalizeProviderProfiles()
        guard let activeId = settings.activeProviderProfileId else { return }
        settings.providerProfiles.removeAll { $0.id == activeId }
        if settings.providerProfiles.isEmpty {
            let profile = AppSettings.defaultProviderProfile(config: ProviderConfig())
            settings.providerProfiles = [profile]
            settings.activeProviderProfileId = profile.id
        } else {
            settings.activeProviderProfileId = settings.providerProfiles.first?.id
        }
        settings.normalizeProviderProfiles()
        applyProviderSettings(settings)
        availableModels = Array(Set(settings.providerConfig.preset.fallbackModels + [settings.providerConfig.model, settings.providerConfig.fastModel])).sorted()
        apiKeyInput = ""
    }

    func updateActiveProviderProfileName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateActiveProviderProfile(resetVerification: false) { profile in
            profile.name = trimmed
        }
    }

    func updateActiveProviderProfileConfig(resetVerification: Bool = true, _ mutate: (inout ProviderConfig) -> Void) {
        updateActiveProviderProfile(resetVerification: resetVerification) { profile in
            mutate(&profile.config)
        }
    }

    func applyProviderPreset(_ preset: ProviderPreset) {
        updateActiveProviderProfile(resetVerification: true) { profile in
            profile.name = profile.name.isEmpty || profile.name == profile.config.preset.displayName
                ? preset.displayName
                : profile.name
            profile.config.preset = preset
            profile.config.baseURL = preset.defaultBaseURL
            profile.config.model = preset.defaultModel
            profile.config.fastModel = preset.defaultFastModel
            profile.config.structuredOutput = preset.defaultStructuredOutput
        }
        availableModels = preset.fallbackModels
        apiKeyInput = ""
    }

    func validateAndSaveProvider() {
        isValidatingProvider = true
        statusMessage = "驗證 provider..."
        Task {
            do {
                var settings = snapshot.settings
                settings.normalizeProviderProfiles()
                guard let activeId = settings.activeProviderProfileId,
                      let activeIndex = settings.providerProfiles.firstIndex(where: { $0.id == activeId }) else {
                    throw LLMClientError.invalidResponse
                }

                let trimmedKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                let candidateKey: String?
                if trimmedKey.isEmpty {
                    let hasStoredKey = try secretStore.hasAPIKey(reference: settings.providerConfig.apiKeyKeychainRef)
                    // Ollama 等本地 endpoint 不需要 key，沒 key 也放行直接驗證連線。
                    guard hasStoredKey || !settings.providerConfig.preset.requiresAPIKey else {
                        await MainActor.run {
                            var missingKeySettings = self.snapshot.settings
                            missingKeySettings.normalizeProviderProfiles()
                            self.updateActiveProviderProfile(in: &missingKeySettings, resetVerification: false) { profile in
                                profile.lastVerifiedAt = Date()
                                profile.lastVerificationStatus = .missingKey
                                profile.lastVerificationMessage = "請貼上 API key 後再驗證。"
                                profile.verifiedModelCount = nil
                            }
                            self.applyProviderSettings(missingKeySettings)
                            self.activeProviderKeyStatus = .missing
                            self.isValidatingProvider = false
                            self.statusMessage = "尚未儲存 API key，請貼上後驗證。"
                        }
                        return
                    }
                    candidateKey = nil
                } else {
                    candidateKey = trimmedKey
                }

                let models = try await providerClient.listModels(settings: settings, apiKeyOverride: candidateKey)

                if let candidateKey {
                    try secretStore.saveAPIKey(candidateKey, reference: settings.providerConfig.apiKeyKeychainRef)
                }
                await MainActor.run {
                    let preset = settings.providerConfig.preset
                    if preset.usesCuratedModelList {
                        self.availableModels = preset.fallbackModels
                    } else {
                        self.availableModels = models.isEmpty ? preset.fallbackModels : models
                    }
                    if !self.availableModels.contains(settings.providerConfig.model),
                       let firstModel = self.availableModels.first {
                        settings.providerConfig.model = firstModel
                        settings.providerProfiles[activeIndex].config.model = firstModel
                    }
                    if !self.availableModels.contains(settings.providerConfig.fastModel),
                       let firstModel = self.availableModels.first {
                        settings.providerConfig.fastModel = firstModel
                        settings.providerProfiles[activeIndex].config.fastModel = firstModel
                    }
                    settings.providerProfiles[activeIndex].lastVerifiedAt = Date()
                    settings.providerProfiles[activeIndex].lastVerificationStatus = .success
                    settings.providerProfiles[activeIndex].lastVerificationMessage = "驗證成功，已取得 \(self.availableModels.count) 個 model。"
                    settings.providerProfiles[activeIndex].verifiedModelCount = self.availableModels.count
                    settings.providerProfiles[activeIndex].updatedAt = Date()
                    settings.normalizeProviderProfiles()
                    self.applyProviderSettings(settings)
                    self.apiKeyInput = ""
                    self.activeProviderKeyStatus = .saved
                    self.isValidatingProvider = false
                    self.statusMessage = "Provider 驗證成功，已取得 \(self.availableModels.count) 個 model"
                }
            } catch {
                await MainActor.run {
                    var settings = self.snapshot.settings
                    settings.normalizeProviderProfiles()
                    self.updateActiveProviderProfile(in: &settings, resetVerification: false) { profile in
                        profile.lastVerifiedAt = Date()
                        profile.lastVerificationStatus = .failed
                        profile.lastVerificationMessage = error.localizedDescription
                        profile.verifiedModelCount = nil
                    }
                    self.applyProviderSettings(settings)
                    self.isValidatingProvider = false
                    self.statusMessage = "驗證失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    func clearActiveProviderProfileKey() {
        guard let profile = snapshot.settings.activeProviderProfile else { return }
        do {
            try secretStore.deleteAPIKey(reference: profile.config.apiKeyKeychainRef)
            var settings = snapshot.settings
            settings.normalizeProviderProfiles()
            updateActiveProviderProfile(in: &settings, resetVerification: false) { profile in
                profile.lastVerifiedAt = Date()
                profile.lastVerificationStatus = .missingKey
                profile.lastVerificationMessage = "API key 已清空。"
                profile.verifiedModelCount = nil
            }
            applyProviderSettings(settings)
            apiKeyInput = ""
            activeProviderKeyStatus = .missing
            statusMessage = "已清空目前 profile 的 API key"
        } catch {
            activeProviderKeyStatus = .error(error.localizedDescription)
            statusMessage = "清空 API key 失敗：\(error.localizedDescription)"
        }
    }

    func refreshActiveProviderKeyStatus() {
        do {
            isOpenAITtsKeySaved = try secretStore.hasAPIKey(reference: snapshot.settings.ttsKeychainReference)
        } catch {
            isOpenAITtsKeySaved = false
        }

        guard let profile = snapshot.settings.activeProviderProfile else {
            activeProviderKeyStatus = .missing
            return
        }
        do {
            activeProviderKeyStatus = try secretStore.hasAPIKey(reference: profile.config.apiKeyKeychainRef) ? .saved : .missing
        } catch {
            activeProviderKeyStatus = .error(error.localizedDescription)
        }
    }

    func saveOpenAITtsKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try secretStore.saveAPIKey(trimmed, reference: snapshot.settings.ttsKeychainReference)
            isOpenAITtsKeySaved = true
            openAITtsKeyInput = ""
            statusMessage = "已儲存 TTS API Key"
            ttsStatusMessage = "已儲存 TTS API Key"
        } catch {
            statusMessage = "儲存 TTS API Key 失敗：\(error.localizedDescription)"
            ttsStatusMessage = statusMessage
        }
    }

    func clearOpenAITtsKey() {
        do {
            try secretStore.deleteAPIKey(reference: snapshot.settings.ttsKeychainReference)
            isOpenAITtsKeySaved = false
            openAITtsKeyInput = ""
            availableTtsModels = []
            availableTtsVoices = []
            statusMessage = "已清除 TTS API Key"
            ttsStatusMessage = "已清除 TTS API Key"
        } catch {
            statusMessage = "清除 TTS API Key 失敗：\(error.localizedDescription)"
            ttsStatusMessage = statusMessage
        }
    }

    var activeTTSProviderProfile: TTSProviderProfile? {
        snapshot.settings.activeTTSProviderProfile
    }

    func selectTTSProviderProfile(_ id: UUID) {
        var settings = snapshot.settings
        guard settings.ttsProviderProfiles.contains(where: { $0.id == id }) else { return }
        settings.activeTTSProviderProfileId = id
        settings.normalizeTTSProviderProfiles()
        applyTTSProviderSettings(settings)
        availableTtsModels = []
        availableTtsVoices = []
        openAITtsKeyInput = ""
    }

    func createTTSProviderProfile(preset: TTSProviderPreset = .openAI) {
        var settings = snapshot.settings
        settings.normalizeTTSProviderProfiles()
        let id = UUID()
        let config = TTSProviderConfig(
            preset: preset,
            baseURL: preset.defaultBaseURL,
            model: preset.defaultModel,
            voice: preset.defaultVoice,
            apiKeyKeychainRef: TTSProviderProfile.keychainReference(for: id)
        )
        let profile = TTSProviderProfile(id: id, name: "新 \(preset.displayName)", config: config)
        settings.ttsProviderProfiles.append(profile)
        settings.activeTTSProviderProfileId = profile.id
        settings.normalizeTTSProviderProfiles()
        applyTTSProviderSettings(settings)
        availableTtsModels = []
        availableTtsVoices = []
        openAITtsKeyInput = ""
    }

    func deleteActiveTTSProviderProfile() {
        var settings = snapshot.settings
        settings.normalizeTTSProviderProfiles()
        guard let activeId = settings.activeTTSProviderProfileId,
              settings.ttsProviderProfiles.count > 1 else { return }
        settings.ttsProviderProfiles.removeAll { $0.id == activeId }
        settings.activeTTSProviderProfileId = settings.ttsProviderProfiles.first?.id
        settings.normalizeTTSProviderProfiles()
        applyTTSProviderSettings(settings)
        availableTtsModels = []
        availableTtsVoices = []
        openAITtsKeyInput = ""
    }

    func updateActiveTTSProviderProfileName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var settings = snapshot.settings
        settings.normalizeTTSProviderProfiles()
        guard let activeId = settings.activeTTSProviderProfileId,
              let index = settings.ttsProviderProfiles.firstIndex(where: { $0.id == activeId }) else { return }
        settings.ttsProviderProfiles[index].name = trimmed
        settings.ttsProviderProfiles[index].updatedAt = Date()
        applyTTSProviderSettings(settings)
    }

    func updateActiveTTSProviderProfileConfig(_ mutate: (inout TTSProviderConfig) -> Void) {
        var settings = snapshot.settings
        settings.normalizeTTSProviderProfiles()
        guard let activeId = settings.activeTTSProviderProfileId,
              let index = settings.ttsProviderProfiles.firstIndex(where: { $0.id == activeId }) else { return }
        mutate(&settings.ttsProviderProfiles[index].config)
        settings.ttsProviderProfiles[index].updatedAt = Date()
        applyTTSProviderSettings(settings)
    }

    /// 切換 TTS provider preset:重設 baseURL/model/voice 為該 preset 預設值
    /// (custom 除外),並清掉已抓取的模型/voice 清單,與主 provider 的
    /// `applyProviderPreset` 同套路。
    func applyTTSProviderPreset(_ preset: TTSProviderPreset) {
        updateActiveTTSProviderProfileConfig { config in
            config.preset = preset
            if preset != .custom {
                config.baseURL = preset.defaultBaseURL
                config.model = preset.defaultModel
                config.voice = preset.defaultVoice
            }
        }
        availableTtsModels = []
        availableTtsVoices = []
        ttsStatusMessage = ""
    }

    /// TTS 一次性搬移:把舊制單一共用 slot 的 key 搬進新制每個 profile 各自
    /// 獨立的 keychain reference,見 `TTSKeychainMigration`。
    private func migrateTTSKeychainReferencesIfNeeded() {
        guard let migrated = TTSKeychainMigration.migrate(settings: snapshot.settings, secretStore: secretStore) else { return }
        applyTTSProviderSettings(migrated)
    }

    private func applyTTSProviderSettings(_ settings: AppSettings) {
        var normalized = settings
        normalized.normalizeTTSProviderProfiles()
        snapshot.settings = normalized
        updateSettings(normalized)
        refreshActiveProviderKeyStatus()
    }

    func fetchAvailableTtsModels() {
        let baseURL = snapshot.settings.openAITtsProviderPreset == .openAI
            ? TTSProviderPreset.openAI.defaultBaseURL
            : snapshot.settings.openAITtsBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isFetchingTtsModels = true
        let loadingMessage = "正在獲取 TTS 可用模型..."
        statusMessage = loadingMessage
        ttsStatusMessage = loadingMessage
        
        guard let apiKey = try? secretStore.apiKey(reference: snapshot.settings.ttsKeychainReference), !apiKey.isEmpty else {
            let message = "請先儲存 API Key 才能獲取模型"
            statusMessage = message
            ttsStatusMessage = message
            isFetchingTtsModels = false
            return
        }

        var baseString = baseURL
        if baseString.hasSuffix("/") {
            baseString.removeLast()
        }

        if snapshot.settings.openAITtsProviderPreset == .gemini {
            availableTtsModels = GeminiTTSOptions.models
            availableTtsVoices = GeminiTTSOptions.voices.map { TTSVoiceOption(id: $0, name: $0) }
            var changes: [String] = []
            if !GeminiTTSOptions.models.contains(snapshot.settings.openAITtsModel),
               let firstModel = GeminiTTSOptions.models.first {
                changes.append("模型 \(firstModel)")
            }
            if !GeminiTTSOptions.voices.contains(snapshot.settings.openAITtsVoice),
               let firstVoice = GeminiTTSOptions.voices.first {
                changes.append("voice \(firstVoice)")
            }
            if !changes.isEmpty {
                updateActiveTTSProviderProfileConfig { config in
                    if !GeminiTTSOptions.models.contains(config.model), let firstModel = GeminiTTSOptions.models.first {
                        config.model = firstModel
                    }
                    if !GeminiTTSOptions.voices.contains(config.voice), let firstVoice = GeminiTTSOptions.voices.first {
                        config.voice = firstVoice
                    }
                }
            }
            let message = "已載入 Gemini TTS：\(GeminiTTSOptions.models.count) 個模型、\(GeminiTTSOptions.voices.count) 個 voices" +
                (changes.isEmpty ? "" : "，並切換到 \(changes.joined(separator: "、"))")
            statusMessage = message
            ttsStatusMessage = message
            isFetchingTtsModels = false
            return
        }

        guard let url = URL(string: "\(baseString)/models") else {
            let message = "API Base URL 格式錯誤"
            statusMessage = message
            ttsStatusMessage = message
            isFetchingTtsModels = false
            return
        }

        if snapshot.settings.openAITtsProviderPreset == .elevenLabs {
            fetchElevenLabsTtsOptions(baseString: baseString, apiKey: apiKey)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isFetchingTtsModels = false
                
                if let error = error {
                    let message = "獲取模型失敗：\(error.localizedDescription)"
                    self.statusMessage = message
                    self.ttsStatusMessage = message
                    return
                }
                guard let data = data else {
                    let message = "獲取模型失敗：伺服器未回傳資料"
                    self.statusMessage = message
                    self.ttsStatusMessage = message
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let result = try decoder.decode(ProviderModelsResponse.self, from: data)
                    let ttsModels = result.ttsModelIDs
                    let diagnostics = result.ttsDiagnostics
                    
                    if ttsModels.isEmpty {
                        self.availableTtsModels = []
                        let message = "未從模型清單辨識到可用 TTS 模型。\(diagnostics.summary)"
                        self.statusMessage = message
                        self.ttsStatusMessage = message
                    } else {
                        self.availableTtsModels = ttsModels
                        if !ttsModels.contains(self.snapshot.settings.openAITtsModel),
                           let firstModel = ttsModels.first {
                            self.updateActiveTTSProviderProfileConfig { $0.model = firstModel }
                            let message = "已成功獲取 \(ttsModels.count) 個 TTS 模型，並切換到 \(firstModel)"
                            self.statusMessage = message
                            self.ttsStatusMessage = message
                        } else {
                            let message = "已成功獲取 \(self.availableTtsModels.count) 個 TTS 模型"
                            self.statusMessage = message
                            self.ttsStatusMessage = message
                        }
                    }
                } catch {
                    let message = "解析模型列表失敗：\(error.localizedDescription)"
                    self.statusMessage = message
                    self.ttsStatusMessage = message
                }
            }
        }.resume()
    }

    private func fetchElevenLabsTtsOptions(baseString: String, apiKey: String) {
        guard let modelsURL = URL(string: "\(baseString)/models"),
              let voicesURL = URL(string: "\(Self.elevenLabsV2BaseURL(from: baseString))/voices?page_size=100") else {
            let message = "ElevenLabs API Base URL 格式錯誤"
            statusMessage = message
            ttsStatusMessage = message
            isFetchingTtsModels = false
            return
        }

        var modelsRequest = URLRequest(url: modelsURL)
        modelsRequest.httpMethod = "GET"
        modelsRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        var voicesRequest = URLRequest(url: voicesURL)
        voicesRequest.httpMethod = "GET"
        voicesRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let voicesRequestToSend = voicesRequest

        struct ElevenLabsModel: Decodable {
            var modelID: String
            var canDoTextToSpeech: Bool?

            enum CodingKeys: String, CodingKey {
                case modelID = "model_id"
                case canDoTextToSpeech = "can_do_text_to_speech"
            }
        }

        struct ElevenLabsVoiceResponse: Decodable {
            struct Voice: Decodable {
                var voiceID: String
                var name: String?

                enum CodingKeys: String, CodingKey {
                    case voiceID = "voice_id"
                    case name
                }
            }

            var voices: [Voice]
        }

        URLSession.shared.dataTask(with: modelsRequest) { [weak self] modelsData, _, modelsError in
            if let modelsError {
                Task { @MainActor in
                    guard let self else { return }
                    self.isFetchingTtsModels = false
                    let message = "獲取 ElevenLabs 模型失敗：\(modelsError.localizedDescription)"
                    self.statusMessage = message
                    self.ttsStatusMessage = message
                }
                return
            }

            URLSession.shared.dataTask(with: voicesRequestToSend) { [weak self] voicesData, _, voicesError in
                Task { @MainActor in
                    guard let self else { return }
                    self.isFetchingTtsModels = false

                    if let voicesError {
                        let message = "獲取 ElevenLabs voices 失敗：\(voicesError.localizedDescription)"
                        self.statusMessage = message
                        self.ttsStatusMessage = message
                        return
                    }

                    do {
                        let decoder = JSONDecoder()
                        let models = try decoder.decode([ElevenLabsModel].self, from: modelsData ?? Data())
                        let voices = try decoder.decode(ElevenLabsVoiceResponse.self, from: voicesData ?? Data())
                        let ttsModels = models
                            .filter { $0.canDoTextToSpeech ?? true }
                            .map(\.modelID)
                            .sorted()
                        let voiceOptions = voices.voices
                            .map { TTSVoiceOption(id: $0.voiceID, name: $0.name ?? $0.voiceID) }
                            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                        self.availableTtsModels = ttsModels
                        self.availableTtsVoices = voiceOptions

                        var changes: [String] = []
                        if !ttsModels.isEmpty,
                           !ttsModels.contains(self.snapshot.settings.openAITtsModel),
                           let firstModel = ttsModels.first {
                            changes.append("模型 \(firstModel)")
                        }
                        if !voiceOptions.isEmpty,
                           !voiceOptions.contains(where: { $0.id == self.snapshot.settings.openAITtsVoice }),
                           let firstVoice = voiceOptions.first {
                            changes.append("voice \(firstVoice.name)")
                        }
                        if !changes.isEmpty {
                            self.updateActiveTTSProviderProfileConfig { config in
                                if !ttsModels.isEmpty, !ttsModels.contains(config.model), let firstModel = ttsModels.first {
                                    config.model = firstModel
                                }
                                if !voiceOptions.isEmpty, !voiceOptions.contains(where: { $0.id == config.voice }), let firstVoice = voiceOptions.first {
                                    config.voice = firstVoice.id
                                }
                            }
                        }

                        let message = "已獲取 ElevenLabs：\(ttsModels.count) 個模型、\(voiceOptions.count) 個 voices" +
                            (changes.isEmpty ? "" : "，並切換到 \(changes.joined(separator: "、"))")
                        self.statusMessage = message
                        self.ttsStatusMessage = message
                    } catch {
                        let message = "解析 ElevenLabs 清單失敗：\(error.localizedDescription)"
                        self.statusMessage = message
                        self.ttsStatusMessage = message
                    }
                }
            }.resume()
        }.resume()
    }

    private static func elevenLabsV2BaseURL(from v1BaseString: String) -> String {
        if v1BaseString.hasSuffix("/v1") {
            return String(v1BaseString.dropLast(3)) + "/v2"
        }
        return v1BaseString
    }

    private func updateActiveProviderProfile(resetVerification: Bool, _ mutate: (inout ProviderProfile) -> Void) {
        var settings = snapshot.settings
        settings.normalizeProviderProfiles()
        updateActiveProviderProfile(in: &settings, resetVerification: resetVerification, mutate)
        applyProviderSettings(settings)
    }

    private func updateActiveProviderProfile(
        in settings: inout AppSettings,
        resetVerification: Bool,
        _ mutate: (inout ProviderProfile) -> Void
    ) {
        settings.normalizeProviderProfiles()
        guard let activeId = settings.activeProviderProfileId,
              let index = settings.providerProfiles.firstIndex(where: { $0.id == activeId }) else { return }
        mutate(&settings.providerProfiles[index])
        settings.providerProfiles[index].updatedAt = Date()
        if resetVerification {
            settings.providerProfiles[index].lastVerifiedAt = nil
            settings.providerProfiles[index].lastVerificationStatus = .unverified
            settings.providerProfiles[index].lastVerificationMessage = nil
            settings.providerProfiles[index].verifiedModelCount = nil
        }
        settings.normalizeProviderProfiles()
    }

    private func applyProviderSettings(_ settings: AppSettings) {
        var normalized = settings
        normalized.normalizeProviderProfiles()
        snapshot.settings = normalized
        updateSettings(normalized)
        refreshActiveProviderKeyStatus()
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
            let traceId = UUID().uuidString
            await AITraceContext.$traceId.withValue(traceId) {
                await AITraceContext.$flow.withValue("generateQuiz") {
                    let startedAt = Date()
                    await AIRequestLogStore.shared.appendEvent(
                        "flow.start",
                        operation: "generateQuiz",
                        message: "Generate quiz questions from learning cards.",
                        input: ["cardCount": "\(cards.count)"]
                    )
                    do {
                        let quizzes = try await providerClient.generateQuiz(cards: cards, settings: snapshot.settings)
                        await AIRequestLogStore.shared.appendEvent(
                            quizzes.isEmpty ? "flow.empty" : "flow.completed",
                            operation: "generateQuiz",
                            output: ["quizCount": "\(quizzes.count)"],
                            startedAt: startedAt
                        )
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
                        await AIRequestLogStore.shared.appendEvent(
                            "flow.failed",
                            operation: "generateQuiz",
                            startedAt: startedAt,
                            errorSummary: error.localizedDescription
                        )
                        await MainActor.run {
                            self.isGeneratingQuiz = false
                            self.statusMessage = "出題失敗：\(error.localizedDescription)"
                        }
                    }
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

                self.presentAbovePopover(panel)
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
            quickReviewCardRemainingSeconds = max(Self.minimumPausedRemainingSeconds, quickReviewCardDeadline.timeIntervalSince(now))
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
        // 快速複習結束後若 popover 仍開著，恢復一般的自動關閉倒數，
        // 否則進度條會停用（變暗且不動）、popover 也永遠不會自動關閉。
        if isPopoverVisible {
            resetAutoCloseForNewCard()
        }
    }

    private func scheduleAutoClose(after duration: TimeInterval) {
        guard isPopoverVisible else { return }
        guard !isQuickReviewActive else { return }
        guard duration > 0 else {
            if isPopoverBusy?() == true {
                scheduleAutoClose(after: schedulerPolicy.visibleDuration(settings: snapshot.settings))
            } else {
                requestClosePopover?()
            }
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
                if self.isPopoverBusy?() == true {
                    self.scheduleAutoClose(after: duration)
                    return
                }
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
            autoCloseRemainingSeconds = max(Self.minimumPausedRemainingSeconds, deadline.timeIntervalSinceNow)
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

    public func popoverDidShow(isMouseInside: Bool = false) {
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

    public func popoverDidClose() {
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

        // 爬蟲與 AI 文章排程屬於內容產生，只在 macOS 執行；
        // iOS 專注學習與 CloudKit 同步，內容由 Mac 版產生。
        #if os(macOS)
        crawlTimer = Timer.scheduledTimer(withTimeInterval: schedulerPolicy.crawlInterval(settings: snapshot.settings), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }

        scheduleNextAIArticleTimer()
        #endif
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

    public func setSelectedVocabularySource(_ source: VocabularySourceType) {
        selectedVocabularySource = source
        shufflePreviewVocabulary()
    }

    public func shufflePreviewVocabulary() {
        let activeCards = snapshot.cards.filter { $0.status != .skipped }
        guard !activeCards.isEmpty else {
            previewVocabularyCards = []
            return
        }

        let candidates: [LearningCard]
        switch selectedVocabularySource {
        case .all:
            candidates = activeCards
        case .recent:
            candidates = Array(activeCards.sorted(by: { $0.createdAt > $1.createdAt }).prefix(20))
        case .unfamiliar:
            let unfamiliarCards = activeCards.filter { $0.status == .new || $0.status == .reviewing }
            if unfamiliarCards.isEmpty {
                candidates = activeCards.sorted(by: { $0.shownCount > $1.shownCount })
            } else {
                candidates = unfamiliarCards
            }
        }

        guard !candidates.isEmpty else {
            previewVocabularyCards = selectBalancedCards(from: activeCards)
            return
        }

        previewVocabularyCards = selectBalancedCards(from: candidates)
    }

    private func selectBalancedCards(from list: [LearningCard]) -> [LearningCard] {
        var shuffledGrammar = list.filter { $0.partOfSpeech == "文法句型" }.shuffled()
        var shuffledVerbs = list.filter { $0.partOfSpeech.contains("動詞") || ($0.verbFormType != .notVerb && $0.verbFormType != .unknown) }.shuffled()
        var shuffledOthers = list.filter { $0.partOfSpeech != "文法句型" && !$0.partOfSpeech.contains("動詞") && $0.verbFormType == .notVerb }.shuffled()

        var selected = [LearningCard]()
        let targetCount = Int.random(in: 5...10)
        
        while selected.count < targetCount && !(shuffledGrammar.isEmpty && shuffledVerbs.isEmpty && shuffledOthers.isEmpty) {
            if !shuffledGrammar.isEmpty {
                selected.append(shuffledGrammar.removeFirst())
            }
            if selected.count < targetCount && !shuffledVerbs.isEmpty {
                selected.append(shuffledVerbs.removeFirst())
            }
            if selected.count < targetCount && !shuffledOthers.isEmpty {
                selected.append(shuffledOthers.removeFirst())
            }
        }
        return selected
    }

    public func generateAIEssayNow() {
        guard !isGeneratingEssay else { return }
        
        let words = previewVocabularyCards.map(\.word)
        guard !words.isEmpty else {
            essayGenerationError = "請先新增或選擇一些單字。"
            return
        }

        isGeneratingEssay = true
        essayCurrentStep = .validating
        essayGenerationProgress = "正在驗證提示詞並擬定短文..."
        essayValidationError = nil
        essayGenerationError = nil
        
        essayGenerationTask = Task {
            let traceId = UUID().uuidString
            await AITraceContext.$traceId.withValue(traceId) {
                await AITraceContext.$flow.withValue("generateAIEssay") {
                    await self.runEssayGeneration(words: words)
                }
            }
        }
    }

    private func runEssayGeneration(words: [String]) async {
        let startedAt = Date()
        await AIRequestLogStore.shared.appendEvent(
            "flow.start",
            operation: "generateAIEssay",
            message: "Generate practice essay from vocabulary words.",
            input: [
                "theme": userEssayPrompt,
                "wordCount": "\(words.count)"
            ]
        )
        do {
            let payload = try await providerClient.generateEssay(
                theme: userEssayPrompt,
                vocabularyWords: words,
                settings: snapshot.settings
            )

            guard payload.isValidPrompt else {
                await AIRequestLogStore.shared.appendEvent(
                    "flow.rejected",
                    operation: "generateAIEssay",
                    message: "Prompt validation failed.",
                    startedAt: startedAt,
                    errorSummary: payload.validationError
                )
                await MainActor.run {
                    self.isGeneratingEssay = false
                    self.essayCurrentStep = nil
                    self.essayValidationError = payload.validationError
                    self.essayGenerationProgress = ""
                }
                return
            }

            try Task.checkCancellation()

            await MainActor.run {
                self.essayCurrentStep = .generatingRuby
                self.essayGenerationProgress = "正在標註漢字讀音..."
            }

            var textsToAnnotate = [payload.title]
            for para in payload.paragraphs {
                textsToAnnotate.append(para.japanese)
            }

            let rubyResults = try await providerClient.generateRubyForTexts(
                texts: textsToAnnotate,
                settings: snapshot.settings
            )

            try Task.checkCancellation()

            let titleRuby = rubyResults.first ?? []
            var paragraphs = [ArticleParagraph]()
            for (index, para) in payload.paragraphs.enumerated() {
                let ruby = (index + 1 < rubyResults.count) ? rubyResults[index + 1] : []
                paragraphs.append(
                    ArticleParagraph(
                        japanese: para.japanese,
                        ruby: ruby,
                        translation: para.translation
                    )
                )
            }

            let plainText = payload.paragraphs.map { "\($0.japanese)\n\($0.translation)" }.joined(separator: "\n\n")
            let levels = Array(Set(previewVocabularyCards.map(\.jlptLevel)))
            let contentHash = ContentHash.sha256(plainText)

            let article = GeneratedArticle(
                kind: .essay,
                theme: userEssayPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "生活化主題" : userEssayPrompt,
                jlptLevels: levels,
                title: payload.title,
                plainText: plainText,
                contentHash: contentHash,
                sourceId: AISource.sentinelSourceId,
                generatedAt: Date(),
                cardCount: previewVocabularyCards.count,
                updatedAt: Date(),
                paragraphs: paragraphs,
                userPrompt: userEssayPrompt,
                vocabularySource: selectedVocabularySource.rawValue,
                vocabularyWords: words,
                titleRuby: titleRuby
            )

            await MainActor.run {
                self.essayCurrentStep = .done
                self.lastGeneratedEssay = article
                self.isGeneratingEssay = false
                self.essayGenerationProgress = ""
                self.statusMessage = "短文「\(payload.title)」產生成功！"
            }

            try await store.update { $0.generatedArticles.insert(article, at: 0) }
            await reload()

            let usableRubyParagraphs = paragraphs.filter { !RubySupport.validated($0.ruby, for: $0.japanese).isEmpty }.count
            await AIRequestLogStore.shared.appendEvent(
                "flow.completed",
                operation: "generateAIEssay",
                output: [
                    "title": payload.title,
                    "paragraphCount": "\(paragraphs.count)",
                    "usableRubyParagraphs": "\(usableRubyParagraphs)",
                    "titleRubyUsable": "\(!RubySupport.validated(titleRuby, for: payload.title).isEmpty)"
                ],
                startedAt: startedAt
            )
        } catch is CancellationError {
            await AIRequestLogStore.shared.appendEvent(
                "flow.cancelled",
                operation: "generateAIEssay",
                message: "Essay generation cancelled by user.",
                startedAt: startedAt
            )
            await MainActor.run {
                self.isGeneratingEssay = false
                self.essayCurrentStep = nil
                self.essayGenerationProgress = ""
                self.statusMessage = "短文產生已取消"
            }
        } catch {
            await AIRequestLogStore.shared.appendEvent(
                "flow.failed",
                operation: "generateAIEssay",
                startedAt: startedAt,
                errorSummary: error.localizedDescription
            )
            await MainActor.run {
                self.isGeneratingEssay = false
                self.essayCurrentStep = nil
                self.essayGenerationProgress = ""
                self.essayGenerationError = "產生失敗：\(error.localizedDescription)"
            }
        }
    }
    
    public func cancelEssayGeneration() {
        essayGenerationTask?.cancel()
        essayCurrentStep = nil
        isGeneratingEssay = false
        essayGenerationProgress = ""
        statusMessage = "短文產生已取消"
    }

    /// 文章任一段落（或標題）缺少可用注音時為 true，供 UI 顯示「重新標註注音」。
    /// 擷取文章尚未段落化時以 resolvedParagraphs 判斷，標註後會一併補上段落。
    public func articleNeedsRubyAnnotation(_ article: GeneratedArticle) -> Bool {
        let paragraphs = article.resolvedParagraphs
        guard !paragraphs.isEmpty else { return false }
        if RubySupport.validated(article.titleRuby, for: article.title).isEmpty && !article.title.isEmpty {
            return true
        }
        return paragraphs.contains { RubySupport.validated($0.ruby, for: $0.japanese).isEmpty }
    }

    /// 補標既有文章的漢字注音（擷取文章／舊資料沒有注音時使用）。
    public func annotateArticleRuby(articleId: UUID) {
        guard !isAnnotatingArticleRuby else { return }
        guard let article = snapshot.generatedArticles.first(where: { $0.id == articleId }) else { return }
        let paragraphs = article.resolvedParagraphs
        guard !paragraphs.isEmpty else { return }

        isAnnotatingArticleRuby = true
        statusMessage = "正在標註漢字讀音..."

        Task {
            let traceId = UUID().uuidString
            await AITraceContext.$traceId.withValue(traceId) {
                await AITraceContext.$flow.withValue("annotateArticleRuby") {
                    let startedAt = Date()
                    await AIRequestLogStore.shared.appendEvent(
                        "flow.start",
                        operation: "annotateArticleRuby",
                        message: "Re-annotate ruby for an existing article.",
                        input: [
                            "articleId": articleId.uuidString,
                            "paragraphCount": "\(paragraphs.count)"
                        ]
                    )
                    do {
                        var textsToAnnotate = [article.title]
                        textsToAnnotate.append(contentsOf: paragraphs.map(\.japanese))
                        let rubyResults = try await providerClient.generateRubyForTexts(
                            texts: textsToAnnotate,
                            settings: snapshot.settings
                        )

                        let titleRuby = RubySupport.validated(rubyResults.first, for: article.title)
                        var updatedParagraphs = paragraphs
                        var annotatedCount = 0
                        for index in updatedParagraphs.indices {
                            let ruby = (index + 1 < rubyResults.count) ? rubyResults[index + 1] : []
                            if !RubySupport.validated(ruby, for: updatedParagraphs[index].japanese).isEmpty {
                                updatedParagraphs[index].ruby = ruby
                                annotatedCount += 1
                            }
                        }

                        let finalParagraphs = updatedParagraphs
                        try await store.update { state in
                            guard let index = state.generatedArticles.firstIndex(where: { $0.id == articleId }) else { return }
                            if !titleRuby.isEmpty {
                                state.generatedArticles[index].titleRuby = titleRuby
                            }
                            state.generatedArticles[index].paragraphs = finalParagraphs
                            state.generatedArticles[index].updatedAt = Date()
                        }
                        await reload()

                        await AIRequestLogStore.shared.appendEvent(
                            "flow.completed",
                            operation: "annotateArticleRuby",
                            output: [
                                "annotatedParagraphs": "\(annotatedCount)",
                                "paragraphCount": "\(finalParagraphs.count)",
                                "titleRubyUsable": "\(!titleRuby.isEmpty)"
                            ],
                            startedAt: startedAt
                        )
                        await MainActor.run {
                            if self.lastGeneratedEssay?.id == articleId {
                                self.lastGeneratedEssay = self.snapshot.generatedArticles.first(where: { $0.id == articleId })
                            }
                            self.isAnnotatingArticleRuby = false
                            self.statusMessage = "注音標註完成"
                        }
                    } catch {
                        await AIRequestLogStore.shared.appendEvent(
                            "flow.failed",
                            operation: "annotateArticleRuby",
                            startedAt: startedAt,
                            errorSummary: error.localizedDescription
                        )
                        await MainActor.run {
                            self.isAnnotatingArticleRuby = false
                            self.statusMessage = "注音標註失敗：\(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    public func exportEssay(article: GeneratedArticle, format: String) {
        let title = article.title
        let fileExtension: String
        switch format {
        case "pdf": fileExtension = "pdf"
        case "png": fileExtension = "png"
        case "word": fileExtension = "docx"
        default: return
        }

        let fileName = "\(title.isEmpty ? "AI短文" : title).\(fileExtension)"

        #if os(macOS)
        let savePanel = NSSavePanel()
        let docType = UTType(filenameExtension: "docx") ?? .data
        savePanel.allowedContentTypes = [
            format == "pdf" ? .pdf : (format == "png" ? .png : docType)
        ]
        savePanel.nameFieldStringValue = fileName
        presentAbovePopover(savePanel)
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try self?.performWriteEssay(article: article, to: url, format: format)
                self?.statusMessage = "已匯出至：\(url.lastPathComponent)"
            } catch {
                self?.statusMessage = "匯出失敗：\(error.localizedDescription)"
            }
        }
        #else
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        do {
            try performWriteEssay(article: article, to: fileURL, format: format)
            self.exportedEssayURL = fileURL
        } catch {
            self.statusMessage = "匯出失敗：\(error.localizedDescription)"
        }
        #endif
    }

    @MainActor
    private func performWriteEssay(article: GeneratedArticle, to url: URL, format: String) throws {
        let title = article.title
        let theme = article.theme
        let paragraphs = article.resolvedParagraphs
        if format == "word" {
            let startedAt = Date()
            let docxData = DocxBuilder.buildDocx(
                title: title,
                titleRuby: article.titleRuby,
                theme: theme,
                paragraphs: paragraphs
            )
            try docxData.write(to: url)

            // 記錄「DB 裡有幾段 ruby、其中幾段通過驗證」。
            // storedRuby > usableRuby 代表舊資料仍含不可用 ruby，匯出時會略過不可用標記。
            let storedRubyParagraphs = paragraphs.filter { !$0.ruby.isEmpty }.count
            let usableRubyParagraphs = paragraphs.filter { !RubySupport.validated($0.ruby, for: $0.japanese).isEmpty }.count
            let titleRubyStored = !(article.titleRuby ?? []).isEmpty
            let titleRubyUsable = !RubySupport.validated(article.titleRuby, for: title).isEmpty
            let fileName = url.lastPathComponent
            let paragraphCount = paragraphs.count
            let articleId = article.id.uuidString
            Task {
                await AITraceContext.$traceId.withValue(UUID().uuidString) {
                    await AITraceContext.$flow.withValue("exportEssayDocx") {
                        await AIRequestLogStore.shared.appendEvent(
                            "flow.start",
                            operation: "exportEssayDocx",
                            message: "Export essay to Word (.docx) with ruby annotations.",
                            input: [
                                "articleId": articleId,
                                "paragraphCount": "\(paragraphCount)"
                            ]
                        )
                        await AIRequestLogStore.shared.appendEvent(
                            "flow.completed",
                            operation: "exportEssayDocx",
                            output: [
                                "fileName": fileName,
                                "storedRubyParagraphs": "\(storedRubyParagraphs)",
                                "usableRubyParagraphs": "\(usableRubyParagraphs)",
                                "titleRubyStored": "\(titleRubyStored)",
                                "titleRubyUsable": "\(titleRubyUsable)"
                            ],
                            startedAt: startedAt
                        )
                    }
                }
            }
            return
        }

        let exportView = VStack(alignment: .leading, spacing: 18) {
            RubyText(
                segments: article.titleRuby ?? [],
                fallback: title,
                baseFont: .system(size: 24, weight: .bold),
                rubyFont: .system(size: 12)
            )
            .frame(maxWidth: .infinity, alignment: .center)
            
            Text("主題：\(theme)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 10)
            
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                VStack(alignment: .leading, spacing: 8) {
                    RubyText(
                        segments: para.ruby,
                        fallback: para.japanese,
                        baseFont: .system(size: 16),
                        rubyFont: .system(size: 9),
                        highlightWords: article.vocabularyWords ?? []
                    )

                    if !para.translation.isEmpty {
                        Text(para.translation)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(36)
        .background(Color.white)
        .colorScheme(.light)
        .frame(width: 595)

        let renderer = ImageRenderer(content: exportView)

        if format == "pdf" {
            renderer.render { size, context in
                var mediaBox = CGRect(origin: .zero, size: size)
                guard let consumer = CGDataConsumer(url: url as CFURL),
                      let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                    return
                }
                pdfContext.beginPDFPage(nil)
                context(pdfContext)
                pdfContext.endPDFPage()
                pdfContext.closePDF()
            }
        } else if format == "png" {
            renderer.scale = 2.0
            #if os(macOS)
            guard let nsImage = renderer.nsImage else {
                throw NSError(domain: "ImageRenderer", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to generate NSImage"])
            }
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ImageRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render PNG data"])
            }
            try pngData.write(to: url)
            #else
            guard let uiImage = renderer.uiImage else {
                throw NSError(domain: "ImageRenderer", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to generate UIImage"])
            }
            guard let pngData = uiImage.pngData() else {
                throw NSError(domain: "ImageRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render PNG data"])
            }
            try pngData.write(to: url)
            #endif
        }
    }
}

public enum EssayGenerationStep: Int, CaseIterable, Sendable {
    case validating = 0
    case generatingRuby = 1
    case done = 2
    
    public var title: String {
        switch self {
        case .validating: return "驗證與擬定短文"
        case .generatingRuby: return "漢字注音標註"
        case .done: return "完成"
        }
    }
}
