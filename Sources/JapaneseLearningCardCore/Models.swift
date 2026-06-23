import Foundation

public struct Source: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var isEnabled: Bool
    public var extractionPrompt: String
    public var lastFetchedAt: Date?
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        isEnabled: Bool = true,
        extractionPrompt: String = "",
        lastFetchedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.url = url
        self.isEnabled = isEnabled
        self.extractionPrompt = extractionPrompt
        self.lastFetchedAt = lastFetchedAt
        self.lastError = lastError
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

    public init(sourceId: UUID, url: URL, title: String, plainText: String, fetchedAt: Date = Date(), contentHash: String) {
        self.sourceId = sourceId
        self.url = url
        self.title = title
        self.plainText = plainText
        self.fetchedAt = fetchedAt
        self.contentHash = contentHash
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

public enum ProviderPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case openCodeGo
    case openCodeZen
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .openCodeGo:
            "OpenCode Go"
        case .openCodeZen:
            "OpenCode Zen"
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
        case .custom:
            "gpt-4.1-mini"
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
        lastShownAt: Date? = nil
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
        answeredAt: Date? = nil
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

    public init(
        preset: ProviderPreset = .openAI,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-4.1-mini",
        apiKeyKeychainRef: String = "default",
        organization: String? = nil,
        project: String? = nil,
        extraHeaders: [String: String] = [:]
    ) {
        self.preset = preset
        self.baseURL = baseURL
        self.model = model
        self.apiKeyKeychainRef = apiKeyKeychainRef
        self.organization = organization
        self.project = project
        self.extraHeaders = extraHeaders
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

    public init(
        id: UUID = UUID(),
        theme: String,
        jlptLevels: [JLPTLevel],
        title: String,
        plainText: String,
        contentHash: String,
        sourceId: UUID,
        generatedAt: Date = Date(),
        cardCount: Int = 0
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
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var displayIntervalMinutes: Int
    public var visibleDurationSeconds: Int
    public var crawlIntervalHours: Int
    public var defaultExtractionPrompt: String
    public var providerConfig: ProviderConfig
    public var aiArticleEnabled: Bool
    public var aiArticleIntervalHours: Int
    public var aiArticleLevels: [JLPTLevel]
    public var aiArticleCustomTheme: String

    public init(
        displayIntervalMinutes: Int = 30,
        visibleDurationSeconds: Int = 20,
        crawlIntervalHours: Int = 6,
        defaultExtractionPrompt: String = "請從網頁文字中挑選適合日文學習的自然日文句子與重要單字。",
        providerConfig: ProviderConfig = ProviderConfig(),
        aiArticleEnabled: Bool = false,
        aiArticleIntervalHours: Int = 12,
        aiArticleLevels: [JLPTLevel] = JLPTLevel.allCases,
        aiArticleCustomTheme: String = ""
    ) {
        self.displayIntervalMinutes = displayIntervalMinutes
        self.visibleDurationSeconds = visibleDurationSeconds
        self.crawlIntervalHours = crawlIntervalHours
        self.defaultExtractionPrompt = defaultExtractionPrompt
        self.providerConfig = providerConfig
        self.aiArticleEnabled = aiArticleEnabled
        self.aiArticleIntervalHours = aiArticleIntervalHours
        self.aiArticleLevels = aiArticleLevels.isEmpty ? JLPTLevel.allCases : aiArticleLevels
        self.aiArticleCustomTheme = aiArticleCustomTheme
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.displayIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .displayIntervalMinutes) ?? 30
        self.visibleDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .visibleDurationSeconds) ?? 20
        self.crawlIntervalHours = try container.decodeIfPresent(Int.self, forKey: .crawlIntervalHours) ?? 6
        self.defaultExtractionPrompt = try container.decodeIfPresent(String.self, forKey: .defaultExtractionPrompt) ?? "請從網頁文字中挑選適合日文學習的自然日文句子與重要單字。"
        self.providerConfig = try container.decodeIfPresent(ProviderConfig.self, forKey: .providerConfig) ?? ProviderConfig()
        self.aiArticleEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiArticleEnabled) ?? false
        self.aiArticleIntervalHours = try container.decodeIfPresent(Int.self, forKey: .aiArticleIntervalHours) ?? 12
        let decodedLevels = try container.decodeIfPresent([JLPTLevel].self, forKey: .aiArticleLevels) ?? JLPTLevel.allCases
        self.aiArticleLevels = decodedLevels.isEmpty ? JLPTLevel.allCases : decodedLevels
        self.aiArticleCustomTheme = try container.decodeIfPresent(String.self, forKey: .aiArticleCustomTheme) ?? ""
    }
}
