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

public struct RubySegment: Codable, Equatable, Sendable {
    public var base: String
    public var ruby: String

    public init(base: String, ruby: String = "") {
        self.base = base
        self.ruby = ruby
    }
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

public enum TTSProviderPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case elevenLabs
    case gemini
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .elevenLabs: "ElevenLabs"
        case .gemini: "Gemini"
        case .custom: "自定義 (Custom)"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .elevenLabs: "https://api.elevenlabs.io/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .custom: "https://api.openai.com/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: "tts-1"
        case .elevenLabs: "eleven_multilingual_v2"
        case .gemini: "gemini-2.5-flash-preview-tts"
        case .custom: "tts-1"
        }
    }

    public var defaultVoice: String {
        switch self {
        case .openAI: "alloy"
        case .elevenLabs: ""
        case .gemini: "Kore"
        case .custom: "alloy"
        }
    }
}

public enum ProviderPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI
    case openCodeGo
    case openCodeZen
    case googleAIStudio
    case ollama
    case custom

    public var id: String { rawValue }

    /// 各 preset 預設是否要求結構化輸出。OpenAI 官方支援，預設開；
    /// 其他第三方/本地 endpoint 不一定支援，預設關以免回 400。
    /// Gemma 透過 Google 的 OpenAI 相容層不保證支援 response_format，預設關。
    /// Ollama 的 OpenAI 相容層支援 response_format，本地小模型更需要 JSON 約束，預設開。
    public var defaultStructuredOutput: StructuredOutputMode {
        switch self {
        case .openAI, .ollama: .jsonObject
        case .openCodeGo, .openCodeZen, .googleAIStudio, .custom: .off
        }
    }

    /// 本地 endpoint（Ollama）不需要 API key；雲端 provider 一律需要。
    public var requiresAPIKey: Bool {
        switch self {
        case .ollama: false
        case .openAI, .openCodeGo, .openCodeZen, .googleAIStudio, .custom: true
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
            "Google AI Studio (Gemini)"
        case .ollama:
            "Ollama（本地）"
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
        case .ollama:
            // Ollama 的 OpenAI 相容端點；模型清單同樣走 GET /v1/models。
            URL(string: "http://127.0.0.1:11434/v1")!
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
            "gemini-3.5-flash"
        case .ollama:
            "qwen3:8b"
        case .custom:
            "gpt-4.1-mini"
        }
    }

    public var defaultFastModel: String {
        switch self {
        case .openAI:
            "gpt-4.1-mini"
        case .openCodeGo:
            "glm-5.2"
        case .openCodeZen:
            "deepseek-v4-flash"
        case .googleAIStudio:
            "gemini-3.1-flash-lite"
        case .ollama:
            "qwen3:8b"
        case .custom:
            "gpt-4.1-mini"
        }
    }

    /// 是否只提供精選的 `fallbackModels` 作為可選模型，不展開 `/models` 的完整清單。
    /// Google AI Studio 會回傳大量模型(含每日額度極低的 Gemini Flash 等)，這裡只給
    /// 免費額度寬鬆的 Gemma；驗證時仍會打 `/models` 確認 API key 有效。
    public var usesCuratedModelList: Bool {
        switch self {
        case .googleAIStudio: false
        case .openAI, .openCodeGo, .openCodeZen, .ollama, .custom: false
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
            ["gemini-3.5-flash", "gemini-3.1-flash-lite", "gemma-4-26b-a4b-it", "gemma-4-31b-it"]
        case .ollama:
            // 驗證時會改抓本機實際安裝的模型清單，這裡只是連不上時的參考值。
            ["qwen3:8b", "qwen3:4b", "gemma3:12b", "llama3.3"]
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
    public var wordRuby: [RubySegment]
    public var exampleRuby: [RubySegment]
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
        wordRuby: [RubySegment] = [],
        exampleRuby: [RubySegment] = [],
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
        self.wordRuby = wordRuby
        self.exampleRuby = exampleRuby
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
        self.wordRuby = try container.decodeIfPresent([RubySegment].self, forKey: .wordRuby) ?? []
        self.exampleRuby = try container.decodeIfPresent([RubySegment].self, forKey: .exampleRuby) ?? []
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
    public var fastModel: String
    public var apiKeyKeychainRef: String
    public var organization: String?
    public var project: String?
    public var extraHeaders: [String: String]
    public var structuredOutput: StructuredOutputMode

    public init(
        preset: ProviderPreset = .openAI,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        model: String = "gpt-4.1-mini",
        fastModel: String = "gpt-4.1-mini",
        apiKeyKeychainRef: String = "default",
        organization: String? = nil,
        project: String? = nil,
        extraHeaders: [String: String] = [:],
        structuredOutput: StructuredOutputMode = .jsonObject
    ) {
        self.preset = preset
        self.baseURL = baseURL
        self.model = model
        self.fastModel = fastModel
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
        self.fastModel = try container.decodeIfPresent(String.self, forKey: .fastModel) ?? container.decodeIfPresent(String.self, forKey: .model) ?? preset.defaultFastModel
        self.apiKeyKeychainRef = try container.decodeIfPresent(String.self, forKey: .apiKeyKeychainRef) ?? "default"
        self.organization = try container.decodeIfPresent(String.self, forKey: .organization)
        self.project = try container.decodeIfPresent(String.self, forKey: .project)
        self.extraHeaders = try container.decodeIfPresent([String: String].self, forKey: .extraHeaders) ?? [:]
        self.structuredOutput = try container.decodeIfPresent(StructuredOutputMode.self, forKey: .structuredOutput) ?? preset.defaultStructuredOutput
    }
}

public enum ProviderVerificationStatus: String, Codable, CaseIterable, Sendable {
    case unverified
    case success
    case failed
    case missingKey
}

public struct ProviderProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var config: ProviderConfig
    public var lastVerifiedAt: Date?
    public var lastVerificationStatus: ProviderVerificationStatus
    public var lastVerificationMessage: String?
    public var verifiedModelCount: Int?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        config: ProviderConfig,
        lastVerifiedAt: Date? = nil,
        lastVerificationStatus: ProviderVerificationStatus = .unverified,
        lastVerificationMessage: String? = nil,
        verifiedModelCount: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.config = config
        self.lastVerifiedAt = lastVerifiedAt
        self.lastVerificationStatus = lastVerificationStatus
        self.lastVerificationMessage = lastVerificationMessage
        self.verifiedModelCount = verifiedModelCount
        self.updatedAt = updatedAt
    }

    /// Keychain 帳號(reference)新制:一律由 profile id 自動產生,與 ProfileID
    /// 一一對應,使用者不可手動編輯。舊資料的搬移見 `ProviderKeychainMigration`。
    public var keychainReference: String {
        Self.keychainReference(for: id)
    }

    public static func keychainReference(for id: UUID) -> String {
        sanitizedKeychainReference(id.uuidString)
    }

    /// 把任意字串轉成安全的 keychain 帳號:白名單(英數、`.`、`-`)以外的字元
    /// 逐 UTF-8 byte 轉成 `_XX`(大寫 hex)。`_` 不在白名單內、本身也會被轉義,
    /// 所以轉換是一對一,兩個不同輸入不會撞出同一個 reference。
    public static func sanitizedKeychainReference(_ raw: String) -> String {
        var result = ""
        result.reserveCapacity(raw.utf8.count)
        for byte in raw.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "."), UInt8(ascii: "-"):
                result.append(Character(UnicodeScalar(byte)))
            default:
                result += String(format: "_%02X", byte)
            }
        }
        return result
    }
}

public struct ArticleParagraph: Codable, Equatable, Sendable {
    public var japanese: String
    public var ruby: [RubySegment]
    public var translation: String

    public init(japanese: String, ruby: [RubySegment] = [], translation: String) {
        self.japanese = japanese
        self.ruby = ruby
        self.translation = translation
    }
}

/// GeneratedArticle 的種類。歷史資料沒有這個欄位，解碼時以
/// 「有沒有 paragraphs」推斷（短文一定有段落，AI 擷取文章沒有）。
public enum GeneratedArticleKind: String, Codable, Sendable {
    /// AI 產生文章並擷取單字卡（造卡用）。
    case extraction
    /// 以既有單字卡產生的複習短文。
    case essay
}

public struct GeneratedArticle: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: GeneratedArticleKind
    public var theme: String
    public var jlptLevels: [JLPTLevel]
    public var title: String
    public var plainText: String
    public var contentHash: String
    public var sourceId: UUID
    public var generatedAt: Date
    public var cardCount: Int
    public var updatedAt: Date
    public var paragraphs: [ArticleParagraph]?
    public var userPrompt: String?
    public var vocabularySource: String?
    public var vocabularyWords: [String]?
    public var titleRuby: [RubySegment]?

    public init(
        id: UUID = UUID(),
        kind: GeneratedArticleKind = .extraction,
        theme: String,
        jlptLevels: [JLPTLevel],
        title: String,
        plainText: String,
        contentHash: String,
        sourceId: UUID,
        generatedAt: Date = Date(),
        cardCount: Int = 0,
        updatedAt: Date = Date(),
        paragraphs: [ArticleParagraph]? = nil,
        userPrompt: String? = nil,
        vocabularySource: String? = nil,
        vocabularyWords: [String]? = nil,
        titleRuby: [RubySegment]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.theme = theme
        self.jlptLevels = jlptLevels
        self.title = title
        self.plainText = plainText
        self.contentHash = contentHash
        self.sourceId = sourceId
        self.generatedAt = generatedAt
        self.cardCount = cardCount
        self.updatedAt = updatedAt
        self.paragraphs = paragraphs
        self.userPrompt = userPrompt
        self.vocabularySource = vocabularySource
        self.vocabularyWords = vocabularyWords
        self.titleRuby = titleRuby
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
        self.paragraphs = try container.decodeIfPresent([ArticleParagraph].self, forKey: .paragraphs)
        self.userPrompt = try container.decodeIfPresent(String.self, forKey: .userPrompt)
        self.vocabularySource = try container.decodeIfPresent(String.self, forKey: .vocabularySource)
        self.vocabularyWords = try container.decodeIfPresent([String].self, forKey: .vocabularyWords)
        self.titleRuby = try container.decodeIfPresent([RubySegment].self, forKey: .titleRuby)
        // 舊資料沒有 kind；未知的新值也退回以 paragraphs 推斷。
        self.kind = (try? container.decodeIfPresent(GeneratedArticleKind.self, forKey: .kind))
            .flatMap { $0 } ?? (self.paragraphs != nil ? .essay : .extraction)
    }

    /// 顯示、注音與匯出用的段落。擷取文章還沒有 paragraphs 時，
    /// 以換行把 plainText 切成純日文段落（translation 留空）。
    /// 舊資料的段落可能殘留 LLM 輸出的 **強調** 標記，這裡一併剝除。
    public var resolvedParagraphs: [ArticleParagraph] {
        if let paragraphs, !paragraphs.isEmpty {
            return paragraphs.map { paragraph in
                var cleaned = paragraph
                cleaned.japanese = RubySupport.strippingEmphasis(paragraph.japanese)
                cleaned.translation = RubySupport.strippingEmphasis(paragraph.translation)
                return cleaned
            }
        }
        return plainText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { ArticleParagraph(japanese: RubySupport.strippingEmphasis($0.trimmingCharacters(in: .whitespaces)), translation: "") }
            .filter { !$0.japanese.isEmpty }
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
    public var providerProfiles: [ProviderProfile]
    public var activeProviderProfileId: UUID?
    public var completedMigrations: [String]
    public var openAITtsEnabled: Bool
    public var openAITtsVoice: String
    public var openAITtsModel: String
    public var openAITtsBaseURL: String
    public var openAITtsProviderPreset: TTSProviderPreset
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
        providerProfiles: [ProviderProfile] = [],
        activeProviderProfileId: UUID? = nil,
        completedMigrations: [String] = [],
        openAITtsEnabled: Bool = false,
        openAITtsVoice: String = "alloy",
        openAITtsModel: String = "tts-1",
        openAITtsBaseURL: String = "https://api.openai.com/v1",
        openAITtsProviderPreset: TTSProviderPreset = .openAI,
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
        self.providerProfiles = providerProfiles
        self.activeProviderProfileId = activeProviderProfileId
        self.completedMigrations = completedMigrations
        self.openAITtsEnabled = openAITtsEnabled
        self.openAITtsVoice = openAITtsVoice
        self.openAITtsModel = openAITtsModel
        self.openAITtsBaseURL = openAITtsBaseURL
        self.openAITtsProviderPreset = openAITtsProviderPreset
        self.updatedAt = updatedAt
        normalizeProviderProfiles()
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

    public static func defaultProviderProfile(config: ProviderConfig = ProviderConfig()) -> ProviderProfile {
        ProviderProfile(id: defaultProviderProfileID, name: config.preset.displayName, config: config, updatedAt: .distantPast)
    }

    private static let defaultProviderProfileID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    public mutating func normalizeProviderProfiles() {
        if providerProfiles.isEmpty {
            let profile = Self.defaultProviderProfile(config: providerConfig)
            providerProfiles = [profile]
            activeProviderProfileId = profile.id
        }

        if activeProviderProfileId == nil || !providerProfiles.contains(where: { $0.id == activeProviderProfileId }) {
            activeProviderProfileId = providerProfiles.first?.id
        }

        if let active = activeProviderProfile {
            providerConfig = active.config
        }
    }

    public var activeProviderProfile: ProviderProfile? {
        guard let activeProviderProfileId else { return providerProfiles.first }
        return providerProfiles.first { $0.id == activeProviderProfileId } ?? providerProfiles.first
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
        self.providerProfiles = try container.decodeIfPresent([ProviderProfile].self, forKey: .providerProfiles) ?? []
        self.activeProviderProfileId = try container.decodeIfPresent(UUID.self, forKey: .activeProviderProfileId)
        self.completedMigrations = try container.decodeIfPresent([String].self, forKey: .completedMigrations) ?? []
        self.openAITtsEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAITtsEnabled) ?? false
        self.openAITtsVoice = try container.decodeIfPresent(String.self, forKey: .openAITtsVoice) ?? "alloy"
        self.openAITtsModel = try container.decodeIfPresent(String.self, forKey: .openAITtsModel) ?? "tts-1"
        self.openAITtsBaseURL = try container.decodeIfPresent(String.self, forKey: .openAITtsBaseURL) ?? "https://api.openai.com/v1"
        if let presetStr = try? container.decode(String.self, forKey: .openAITtsProviderPreset),
           let preset = TTSProviderPreset(rawValue: presetStr) {
            self.openAITtsProviderPreset = preset
        } else {
            self.openAITtsProviderPreset = .openAI
        }
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        normalizeProviderProfiles()
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

public enum VocabularySourceType: String, Codable, CaseIterable, Sendable {
    case all = "全部的單字"
    case recent = "最近加入的單字"
    case unfamiliar = "不熟的單字"
}
