import Foundation

public struct Source: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var isEnabled: Bool
    public var extractionPrompt: String
    public var lastFetchedAt: Date?
    public var lastError: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        url: URL,
        isEnabled: Bool = true,
        extractionPrompt: String = "",
        lastFetchedAt: Date? = nil,
        lastError: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.isEnabled = isEnabled
        self.extractionPrompt = extractionPrompt
        self.lastFetchedAt = lastFetchedAt
        self.lastError = lastError
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.url = try container.decode(URL.self, forKey: .url)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.extractionPrompt = try container.decodeIfPresent(String.self, forKey: .extractionPrompt) ?? ""
        self.lastFetchedAt = try container.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        self.lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct CrawledDocument: Codable, Identifiable, Equatable, Sendable {
    public var id: String { contentHash }
    public var sourceId: UUID
    public var url: URL
    public var title: String
    public var plainText: String
    public var fetchedAt: Date
    public var contentHash: String
    public var updatedAt: Date

    public init(sourceId: UUID, url: URL, title: String, plainText: String, fetchedAt: Date = Date(), contentHash: String, updatedAt: Date = Date()) {
        self.sourceId = sourceId
        self.url = url
        self.title = title
        self.plainText = plainText
        self.fetchedAt = fetchedAt
        self.contentHash = contentHash
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceId = try container.decode(UUID.self, forKey: .sourceId)
        self.url = try container.decode(URL.self, forKey: .url)
        self.title = try container.decode(String.self, forKey: .title)
        self.plainText = try container.decode(String.self, forKey: .plainText)
        self.fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? Date()
        self.contentHash = try container.decode(String.self, forKey: .contentHash)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public enum CardStatus: String, Codable, CaseIterable, Sendable {
    case new
    case reviewing
    case learned
    case skipped
}

public enum QuizStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case correct
    case incorrect
    case skipped
}

public enum JLPTLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case n1 = "N1"
    case n2 = "N2"
    case n3 = "N3"
    case n4 = "N4"
    case n5 = "N5"
    case unknown = "Unknown"

    public var id: String { rawValue }
}

public enum AISource {
    public static let sentinelSourceId = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    public static let sentinelURL = URL(string: "ai-article://generator")!
    public static let sentinelExtractionPrompt = "請從這篇 AI 生成的文章中挑選適合日文學習的自然日文句子與重要單字。文章主題：%@，目標 JLPT 等級：%@。"

    public static func makeExtractionPrompt(theme: String, levels: String) -> String {
        String(format: sentinelExtractionPrompt, theme, levels)
    }

    public static func isSentinelSource(_ source: Source) -> Bool {
        source.id == sentinelSourceId || source.url == sentinelURL
    }
}

public enum VerbFormType: String, Codable, CaseIterable, Identifiable, Sendable {
    case ichidan = "一段動詞"
    case godan = "五段動詞"
    case suru = "する動詞"
    case kuru = "くる動詞"
    case irregular = "不規則動詞"
    case notVerb = "非動詞"
    case unknown = "不明"

    public var id: String { rawValue }
}

/// 是否在請求中加入 OpenAI 相容的 `response_format`，要求模型只輸出 JSON。
/// 與模型無關的「主動」治本手段；不支援此欄位的 endpoint 應設為 .off。
public enum StructuredOutputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case jsonObject

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "關閉"
        case .jsonObject: "JSON 物件 (json_object)"
        }
    }
}

public enum ProviderPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case openCodeGo
    case openCodeZen
    case googleAIStudio
    case custom

    public var id: String { rawValue }

    /// 各 preset 預設是否要求結構化輸出。OpenAI 官方支援，預設開；
    /// 其他第三方/本地 endpoint 不一定支援，預設關以免回 400。
    /// Gemma 透過 Google 的 OpenAI 相容層不保證支援 response_format，預設關。
    public var defaultStructuredOutput: StructuredOutputMode {
        switch self {
        case .openAI: .jsonObject
        case .openCodeGo, .openCodeZen, .googleAIStudio, .custom: .off
        }
    }

    public var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .openCodeGo:
            "OpenCode Go"
        case .openCodeZen:
            "OpenCode Zen"
        case .googleAIStudio:
            "Google AI Studio (Gemma)"
        case .custom:
            "Custom"
        }
    }

    public var defaultBaseURL: URL {
        switch self {
        case .openAI:
            URL(string: "https://api.openai.com/v1")!
        case .openCodeGo:
            URL(string: "https://opencode.ai/zen/go/v1")!
        case .openCodeZen:
            URL(string: "https://opencode.ai/zen/v1")!
        case .googleAIStudio:
            // Google AI Studio / Gemini API 的 OpenAI 相容端點。
            URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        case .custom:
            URL(string: "https://api.openai.com/v1")!
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI:
            "gpt-4.1-mini"
        case .openCodeGo:
            "glm-5.2"
        case .openCodeZen:
            "deepseek-v4-flash"
        case .googleAIStudio:
            // Gemma 4 小而快、有免費額度(A4B = 活躍約 4B 參數)。
            "gemma-4-26b-a4b-it"
        case .custom:
            "gpt-4.1-mini"
        }
    }

    /// 是否只提供精選的 `fallbackModels` 作為可選模型，不展開 `/models` 的完整清單。
    /// Google AI Studio 會回傳大量模型(含每日額度極低的 Gemini Flash 等)，這裡只給
    /// 免費額度寬鬆的 Gemma；驗證時仍會打 `/models` 確認 API key 有效。
    public var usesCuratedModelList: Bool {
        switch self {
        case .googleAIStudio: true
        case .openAI, .openCodeGo, .openCodeZen, .custom: false
        }
    }

    public var fallbackModels: [String] {
        switch self {
        case .openAI:
            ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"]
        case .openCodeGo:
            ["glm-5.2", "glm-5.1", "kimi-k2.7", "kimi-k2.6", "deepseek-v4-pro", "deepseek-v4-flash", "mimo-v2.5", "mimo-v2.5-pro"]
        case .openCodeZen:
            ["deepseek-v4-flash", "deepseek-v4-pro", "minimax-m2.7", "minimax-m2.5", "glm-5.2", "glm-5.1", "kimi-k2.6", "big-pickle"]
        case .googleAIStudio:
            // 只列 Gemma：免費額度寬鬆(15 RPM、token 無上限、每日 1500 次)。
            // 不放 Gemini Flash——其免費額度每日僅約 20 次，生卡片很快就爆。
            // 想用其他模型可在「驗證並儲存」後從 /models 抓到的清單選。
            ["gemma-4-26b-a4b-it", "gemma-4-31b-it"]
        case .custom:
            [defaultModel]
        }
    }
}

public struct LearningCard: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var word: String
    public var reading: String
    public var partOfSpeech: String
    public var meaningZh: String
    public var grammarNoteZh: String
    public var jlptLevel: JLPTLevel
    public var verbFormType: VerbFormType
    public var exampleJa: String
    public var exampleReading: String
    public var exampleZh: String
    public var sourceUrl: URL
    public var status: CardStatus
    public var createdAt: Date
    public var lastShownAt: Date?
    public var shownCount: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        word: String,
        reading: String,
        partOfSpeech: String,
        meaningZh: String,
        grammarNoteZh: String,
        jlptLevel: JLPTLevel = .unknown,
        verbFormType: VerbFormType = .notVerb,
        exampleJa: String,
        exampleReading: String = "",
        exampleZh: String,
        sourceUrl: URL,
        status: CardStatus = .new,
        createdAt: Date = Date(),
        lastShownAt: Date? = nil,
        shownCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.word = word
        self.reading = reading
        self.partOfSpeech = partOfSpeech
        self.meaningZh = meaningZh
        self.grammarNoteZh = grammarNoteZh
        self.jlptLevel = jlptLevel
        self.verbFormType = verbFormType
        self.exampleJa = exampleJa
        self.exampleReading = exampleReading
        self.exampleZh = exampleZh
        self.sourceUrl = sourceUrl
        self.status = status
        self.createdAt = createdAt
        self.lastShownAt = lastShownAt
        self.shownCount = shownCount
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.word = try container.decode(String.self, forKey: .word)
        self.reading = try container.decode(String.self, forKey: .reading)
        self.partOfSpeech = try container.decode(String.self, forKey: .partOfSpeech)
        self.meaningZh = try container.decode(String.self, forKey: .meaningZh)
        self.grammarNoteZh = try container.decode(String.self, forKey: .grammarNoteZh)
        self.jlptLevel = try container.decodeIfPresent(JLPTLevel.self, forKey: .jlptLevel) ?? .unknown
        self.verbFormType = try container.decodeIfPresent(VerbFormType.self, forKey: .verbFormType) ?? .notVerb
        self.exampleJa = try container.decode(String.self, forKey: .exampleJa)
        self.exampleReading = try container.decodeIfPresent(String.self, forKey: .exampleReading) ?? ""
        self.exampleZh = try container.decode(String.self, forKey: .exampleZh)
        self.sourceUrl = try container.decode(URL.self, forKey: .sourceUrl)
        self.status = try container.decodeIfPresent(CardStatus.self, forKey: .status) ?? .new
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.lastShownAt = try container.decodeIfPresent(Date.self, forKey: .lastShownAt)
        self.shownCount = try container.decodeIfPresent(Int.self, forKey: .shownCount) ?? 0
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct QuizQuestion: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var cardId: UUID?
    public var sourceWord: String
    public var question: String
    public var choices: [String]
    public var correctAnswer: String
    public var explanationZh: String
    public var status: QuizStatus
    public var selectedAnswer: String?
    public var createdAt: Date
    public var answeredAt: Date?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        cardId: UUID? = nil,
        sourceWord: String,
        question: String,
        choices: [String],
        correctAnswer: String,
        explanationZh: String,
        status: QuizStatus = .pending,
        selectedAnswer: String? = nil,
        createdAt: Date = Date(),
        answeredAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.cardId = cardId
        self.sourceWord = sourceWord
        self.question = question
        self.choices = choices
        self.correctAnswer = correctAnswer
        self.explanationZh = explanationZh
        self.status = status
        self.selectedAnswer = selectedAnswer
        self.createdAt = createdAt
        self.answeredAt = answeredAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.cardId = try container.decodeIfPresent(UUID.self, forKey: .cardId)
        self.sourceWord = try container.decode(String.self, forKey: .sourceWord)
        self.question = try container.decode(String.self, forKey: .question)
        self.choices = try container.decode([String].self, forKey: .choices)
        self.correctAnswer = try container.decode(String.self, forKey: .correctAnswer)
        self.explanationZh = try container.decode(String.self, forKey: .explanationZh)
        self.status = try container.decodeIfPresent(QuizStatus.self, forKey: .status) ?? .pending
        self.selectedAnswer = try container.decodeIfPresent(String.self, forKey: .selectedAnswer)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.answeredAt = try container.decodeIfPresent(Date.self, forKey: .answeredAt)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct ProviderConfig: Codable, Equatable, Sendable {
    public var preset: ProviderPreset
    public var baseURL: URL
    public var model: String
    public var apiKeyKeychainRef: String
    public var organization: String?
    public var project: String?
    public var extraHeaders: [String: String]
    public var structuredOutput: StructuredOutputMode

    public init(
        preset: ProviderPreset = .openAI,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-4.1-mini",
        apiKeyKeychainRef: String = "default",
        organization: String? = nil,
        project: String? = nil,
        extraHeaders: [String: String] = [:],
        structuredOutput: StructuredOutputMode = .jsonObject
    ) {
        self.preset = preset
        self.baseURL = baseURL
        self.model = model
        self.apiKeyKeychainRef = apiKeyKeychainRef
        self.organization = organization
        self.project = project
        self.extraHeaders = extraHeaders
        self.structuredOutput = structuredOutput
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preset = try container.decodeIfPresent(ProviderPreset.self, forKey: .preset) ?? .openAI
        self.baseURL = try container.decodeIfPresent(URL.self, forKey: .baseURL) ?? preset.defaultBaseURL
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? preset.defaultModel
        self.apiKeyKeychainRef = try container.decodeIfPresent(String.self, forKey: .apiKeyKeychainRef) ?? "default"
        self.organization = try container.decodeIfPresent(String.self, forKey: .organization)
        self.project = try container.decodeIfPresent(String.self, forKey: .project)
        self.extraHeaders = try container.decodeIfPresent([String: String].self, forKey: .extraHeaders) ?? [:]
        self.structuredOutput = try container.decodeIfPresent(StructuredOutputMode.self, forKey: .structuredOutput) ?? preset.defaultStructuredOutput
    }
}

public struct GeneratedArticle: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var theme: String
    public var jlptLevels: [JLPTLevel]
    public var title: String
    public var plainText: String
    public var contentHash: String
    public var sourceId: UUID
    public var generatedAt: Date
    public var cardCount: Int
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        theme: String,
        jlptLevels: [JLPTLevel],
        title: String,
        plainText: String,
        contentHash: String,
        sourceId: UUID,
        generatedAt: Date = Date(),
        cardCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.theme = theme
        self.jlptLevels = jlptLevels
        self.title = title
        self.plainText = plainText
        self.contentHash = contentHash
        self.sourceId = sourceId
        self.generatedAt = generatedAt
        self.cardCount = cardCount
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.theme = try container.decode(String.self, forKey: .theme)
        self.jlptLevels = try container.decodeIfPresent([JLPTLevel].self, forKey: .jlptLevels) ?? []
        self.title = try container.decode(String.self, forKey: .title)
        self.plainText = try container.decode(String.self, forKey: .plainText)
        self.contentHash = try container.decode(String.self, forKey: .contentHash)
        self.sourceId = try container.decode(UUID.self, forKey: .sourceId)
        self.generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        self.cardCount = try container.decodeIfPresent(Int.self, forKey: .cardCount) ?? 0
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let legacyDefaultExtractionPrompt = "請從網頁文字中挑選適合日文學習的自然日文句子與重要單字。"
    public static let currentDefaultExtractionPrompt = "請從網頁文字中挑選適合日文學習的自然日文句子、重要單字／片語，以及可學習的文法句型。"

    public var displayIntervalMinutes: Int
    public var visibleDurationSeconds: Int
    public var quickReviewDurationMinutes: Int
    public var quickReviewCardIntervalSeconds: Int
    public var crawlIntervalHours: Int
    public var defaultExtractionPrompt: String
    public var providerConfig: ProviderConfig
    public var aiArticleEnabled: Bool
    public var aiArticleIntervalHours: Int
    /// 排程時間（時，0...23），搭配 aiArticleWeekdays 決定每日觸發時刻。
    public var aiArticleScheduleHour: Int
    /// 排程時間（分，0...59）。
    public var aiArticleScheduleMinute: Int
    /// 觸發的星期幾，使用 Calendar 慣例（1 = 週日 … 7 = 週六）。空陣列代表不觸發。
    public var aiArticleWeekdays: [Int]
    public var aiArticleLevels: [JLPTLevel]
    public var aiArticleCustomTheme: String
    public var updatedAt: Date

    public init(
        displayIntervalMinutes: Int = 30,
        visibleDurationSeconds: Int = 20,
        quickReviewDurationMinutes: Int = 3,
        quickReviewCardIntervalSeconds: Int = 20,
        crawlIntervalHours: Int = 6,
        defaultExtractionPrompt: String = Self.currentDefaultExtractionPrompt,
        providerConfig: ProviderConfig = ProviderConfig(),
        aiArticleEnabled: Bool = false,
        aiArticleIntervalHours: Int = 12,
        aiArticleScheduleHour: Int = 9,
        aiArticleScheduleMinute: Int = 0,
        aiArticleWeekdays: [Int] = [1, 2, 3, 4, 5, 6, 7],
        aiArticleLevels: [JLPTLevel] = JLPTLevel.allCases,
        aiArticleCustomTheme: String = "",
        updatedAt: Date = Date()
    ) {
        self.displayIntervalMinutes = displayIntervalMinutes
        self.visibleDurationSeconds = visibleDurationSeconds
        self.quickReviewDurationMinutes = max(1, quickReviewDurationMinutes)
        self.quickReviewCardIntervalSeconds = max(5, quickReviewCardIntervalSeconds)
        self.crawlIntervalHours = crawlIntervalHours
        self.defaultExtractionPrompt = Self.normalizedDefaultExtractionPrompt(defaultExtractionPrompt)
        self.providerConfig = providerConfig
        self.aiArticleEnabled = aiArticleEnabled
        self.aiArticleIntervalHours = aiArticleIntervalHours
        self.aiArticleScheduleHour = AppSettings.clampHour(aiArticleScheduleHour)
        self.aiArticleScheduleMinute = AppSettings.clampMinute(aiArticleScheduleMinute)
        self.aiArticleWeekdays = AppSettings.normalizeWeekdays(aiArticleWeekdays)
        self.aiArticleLevels = aiArticleLevels.isEmpty ? JLPTLevel.allCases : aiArticleLevels
        self.aiArticleCustomTheme = aiArticleCustomTheme
        self.updatedAt = updatedAt
    }

    public static func clampHour(_ value: Int) -> Int { min(23, max(0, value)) }
    public static func clampMinute(_ value: Int) -> Int { min(59, max(0, value)) }
    public static func normalizedDefaultExtractionPrompt(_ value: String) -> String {
        value == legacyDefaultExtractionPrompt ? currentDefaultExtractionPrompt : value
    }

    /// 去重、過濾無效值並排序，星期幾以 Calendar 慣例（1...7）表示。
    public static func normalizeWeekdays(_ values: [Int]) -> [Int] {
        Array(Set(values.filter { (1...7).contains($0) })).sorted()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displayIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .displayIntervalMinutes) ?? 30
        self.visibleDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .visibleDurationSeconds) ?? 20
        self.quickReviewDurationMinutes = max(1, try container.decodeIfPresent(Int.self, forKey: .quickReviewDurationMinutes) ?? 3)
        self.quickReviewCardIntervalSeconds = max(5, try container.decodeIfPresent(Int.self, forKey: .quickReviewCardIntervalSeconds) ?? 20)
        self.crawlIntervalHours = try container.decodeIfPresent(Int.self, forKey: .crawlIntervalHours) ?? 6
        let decodedExtractionPrompt = try container.decodeIfPresent(String.self, forKey: .defaultExtractionPrompt) ?? Self.currentDefaultExtractionPrompt
        self.defaultExtractionPrompt = Self.normalizedDefaultExtractionPrompt(decodedExtractionPrompt)
        self.providerConfig = try container.decodeIfPresent(ProviderConfig.self, forKey: .providerConfig) ?? ProviderConfig()
        self.aiArticleEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiArticleEnabled) ?? false
        self.aiArticleIntervalHours = try container.decodeIfPresent(Int.self, forKey: .aiArticleIntervalHours) ?? 12
        self.aiArticleScheduleHour = AppSettings.clampHour(try container.decodeIfPresent(Int.self, forKey: .aiArticleScheduleHour) ?? 9)
        self.aiArticleScheduleMinute = AppSettings.clampMinute(try container.decodeIfPresent(Int.self, forKey: .aiArticleScheduleMinute) ?? 0)
        self.aiArticleWeekdays = AppSettings.normalizeWeekdays(try container.decodeIfPresent([Int].self, forKey: .aiArticleWeekdays) ?? [1, 2, 3, 4, 5, 6, 7])
        let decodedLevels = try container.decodeIfPresent([JLPTLevel].self, forKey: .aiArticleLevels) ?? JLPTLevel.allCases
        self.aiArticleLevels = decodedLevels.isEmpty ? JLPTLevel.allCases : decodedLevels
        self.aiArticleCustomTheme = try container.decodeIfPresent(String.self, forKey: .aiArticleCustomTheme) ?? ""
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// 標記可以參與 iCloud 3-way merge 的 model。`updatedAt` 是 LWW 與衝突偵測
/// 的依據, 由 `AppStore.update()` 在每次寫入時自動更新。
public protocol MergeTrackable: Codable, Equatable, Sendable {
    var updatedAt: Date { get set }
}

extension Source: MergeTrackable {}
extension CrawledDocument: MergeTrackable {}
extension LearningCard: MergeTrackable {}
extension QuizQuestion: MergeTrackable {}
extension GeneratedArticle: MergeTrackable {}
extension AppSettings: MergeTrackable {}
