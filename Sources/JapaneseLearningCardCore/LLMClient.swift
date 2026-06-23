import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LLMClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case noContent

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Missing API key."
        case .invalidResponse:
            "The provider returned an invalid response."
        case .noContent:
            "The provider returned no content."
        }
    }
}

public protocol LLMClient: Sendable {
    func generateCards(document: CrawledDocument, sourcePrompt: String, settings: AppSettings) async throws -> [LearningCard]
    func generateQuiz(cards: [LearningCard], settings: AppSettings) async throws -> [QuizQuestion]
    func generateArticle(theme: String, jlptLevels: [JLPTLevel], settings: AppSettings) async throws -> AIArticleDraft
}

public struct AIArticleDraft: Codable, Equatable, Sendable {
    public var theme: String
    public var title: String
    public var text: String

    public init(theme: String, title: String, text: String) {
        self.theme = theme
        self.title = title
        self.text = text
    }
}

public struct OpenAICompatibleLLMClient: LLMClient {
    public static let userAgent = WebCrawler.userAgent

    private let secretStore: SecretStore
    private let session: URLSession

    public init(secretStore: SecretStore = KeychainStore(), session: URLSession = OpenAICompatibleLLMClient.makeDefaultSession()) {
        self.secretStore = secretStore
        self.session = session
    }

    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }

    public func generateCards(document: CrawledDocument, sourcePrompt: String, settings: AppSettings) async throws -> [LearningCard] {
        guard let apiKey = try secretStore.apiKey(reference: settings.providerConfig.apiKeyKeychainRef), !apiKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }

        let body = Self.requestBody(document: document, sourcePrompt: sourcePrompt, settings: settings)
        var request = URLRequest(url: settings.providerConfig.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let organization = settings.providerConfig.organization, !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let project = settings.providerConfig.project, !project.isEmpty {
            request.setValue(project, forHTTPHeaderField: "OpenAI-Project")
        }
        for (key, value) in settings.providerConfig.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMClientError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMClientError.noContent
        }
        return try Self.decodeCards(from: content, sourceURL: document.url)
    }

    public func generateQuiz(cards: [LearningCard], settings: AppSettings) async throws -> [QuizQuestion] {
        guard let apiKey = try secretStore.apiKey(reference: settings.providerConfig.apiKeyKeychainRef), !apiKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }

        let body = Self.quizRequestBody(cards: cards, settings: settings)
        var request = URLRequest(url: settings.providerConfig.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let organization = settings.providerConfig.organization, !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let project = settings.providerConfig.project, !project.isEmpty {
            request.setValue(project, forHTTPHeaderField: "OpenAI-Project")
        }
        for (key, value) in settings.providerConfig.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMClientError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMClientError.noContent
        }
        return try Self.decodeQuiz(from: content, cards: cards)
    }

    public func generateExampleReading(exampleJa: String, settings: AppSettings) async throws -> String {
        guard let apiKey = try secretStore.apiKey(reference: settings.providerConfig.apiKeyKeychainRef), !apiKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }

        let body = ChatCompletionRequest(
            model: settings.providerConfig.model,
            messages: [
                .init(role: "system", content: """
                你是日文假名標註器。只輸出 JSON，不要 Markdown。
                JSON schema: {"exampleReading":"..."}
                exampleReading 必須把輸入日文句子完整轉成平假名讀音；漢字要轉成正確平假名，助詞保留原本讀音，不要羅馬拼音。
                """),
                .init(role: "user", content: exampleJa)
            ],
            temperature: 0.1
        )

        var request = URLRequest(url: settings.providerConfig.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let organization = settings.providerConfig.organization, !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let project = settings.providerConfig.project, !project.isEmpty {
            request.setValue(project, forHTTPHeaderField: "OpenAI-Project")
        }
        for (key, value) in settings.providerConfig.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMClientError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMClientError.noContent
        }
        return try Self.decodeExampleReading(from: content)
    }

    public func generateArticle(theme: String, jlptLevels: [JLPTLevel], settings: AppSettings) async throws -> AIArticleDraft {
        guard let apiKey = try secretStore.apiKey(reference: settings.providerConfig.apiKeyKeychainRef), !apiKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }

        let body = Self.articleRequestBody(theme: theme, jlptLevels: jlptLevels, settings: settings)
        var request = URLRequest(url: settings.providerConfig.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let organization = settings.providerConfig.organization, !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let project = settings.providerConfig.project, !project.isEmpty {
            request.setValue(project, forHTTPHeaderField: "OpenAI-Project")
        }
        for (key, value) in settings.providerConfig.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMClientError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMClientError.noContent
        }
        return try Self.decodeArticle(from: content, fallbackTheme: theme)
    }

    public func listModels(settings: AppSettings) async throws -> [String] {
        guard let apiKey = try secretStore.apiKey(reference: settings.providerConfig.apiKeyKeychainRef), !apiKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }

        var request = URLRequest(url: settings.providerConfig.baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let organization = settings.providerConfig.organization, !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let project = settings.providerConfig.project, !project.isEmpty {
            request.setValue(project, forHTTPHeaderField: "OpenAI-Project")
        }
        for (key, value) in settings.providerConfig.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LLMClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map(\.id).sorted()
    }

    public static func requestBody(document: CrawledDocument, sourcePrompt: String, settings: AppSettings) -> ChatCompletionRequest {
        let extractionPrompt = sourcePrompt.isEmpty ? settings.defaultExtractionPrompt : sourcePrompt
        return ChatCompletionRequest(
            model: settings.providerConfig.model,
            messages: [
                .init(role: "system", content: """
                你是日文學習卡產生器。只輸出 JSON，不要 Markdown。
                JSON schema: {"cards":[{"word":"...","reading":"...","partOfSpeech":"...","meaningZh":"...","grammarNoteZh":"...","jlptLevel":"N1|N2|N3|N4|N5|Unknown","verbFormType":"一段動詞|五段動詞|する動詞|くる動詞|不規則動詞|非動詞|不明","exampleJa":"...","exampleReading":"...","exampleZh":"..."}]}
                不要輸出 JLPT N5 的單字或文法點；若判定為 N5，請直接略過該卡。
                jlptLevel 必須標註 N1、N2、N3、N4、N5 或 Unknown。
                如果 partOfSpeech 是動詞，verbFormType 必須標註動詞型態；如果不是動詞，verbFormType 使用「非動詞」。
                exampleReading 是必填欄位，必須把 exampleJa 整句完整轉成平假名讀音；漢字必須轉成正確平假名，助詞保留原本讀音，不要使用羅馬拼音。
                請使用繁體中文解說。最多產生 5 張卡。
                """),
                .init(role: "user", content: """
                使用者想抓取的範圍：
                \(extractionPrompt)

                來源標題：\(document.title)
                來源網址：\(document.url.absoluteString)

                網頁文字：
                \(String(document.plainText.prefix(12000)))
                """)
            ],
            temperature: 0.4
        )
    }

    public static func quizRequestBody(cards: [LearningCard], settings: AppSettings) -> ChatCompletionRequest {
        let source = cards.prefix(12).map {
            """
            - id: \($0.id.uuidString)
              word: \($0.word)
              reading: \($0.reading)
              partOfSpeech: \($0.partOfSpeech)
              meaningZh: \($0.meaningZh)
              grammarNoteZh: \($0.grammarNoteZh)
              jlptLevel: \($0.jlptLevel.rawValue)
              verbFormType: \($0.verbFormType.rawValue)
              exampleJa: \($0.exampleJa)
              exampleReading: \($0.exampleReading)
              exampleZh: \($0.exampleZh)
            """
        }.joined(separator: "\n")

        return ChatCompletionRequest(
            model: settings.providerConfig.model,
            messages: [
                .init(role: "system", content: """
                你是日文學習測驗老師。只輸出 JSON，不要 Markdown。
                JSON schema: {"quizzes":[{"cardId":"可省略","sourceWord":"...","question":"...","choices":["A","B","C","D"],"correctAnswer":"...","explanationZh":"..."}]}
                題目要測單字意思、用法、助詞、文法或例句理解。請用繁體中文寫解析。每題必須剛好 4 個選項，correctAnswer 必須完全等於其中一個 choices。
                """),
                .init(role: "user", content: """
                請根據以下學習卡產生最多 5 題選擇題：

                \(source)
                """)
            ],
            temperature: 0.35
        )
    }

    public static func articleRequestBody(theme: String, jlptLevels: [JLPTLevel], settings: AppSettings) -> ChatCompletionRequest {
        let levelList: String
        if jlptLevels.isEmpty {
            levelList = JLPTLevel.allCases.map(\.rawValue).joined(separator: "、")
        } else {
            levelList = jlptLevels.map(\.rawValue).joined(separator: "、")
        }
        let isRandomTheme = theme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let resolvedTheme = isRandomTheme ? "(請隨機挑選一個有趣、生活化的日文主題)" : theme
        let levelGuidance = jlptLevels.contains(.n5) || jlptLevels.isEmpty
            ? "若目標包含 N5，可使用 N5 等級的字彙與文法。"
            : "請勿使用 JLPT N5 的單字或文法點；至少 N4 以上。"

        return ChatCompletionRequest(
            model: settings.providerConfig.model,
            messages: [
                .init(role: "system", content: """
                你是日文學習文章作者。只輸出 JSON，不要 Markdown。
                JSON schema: {"theme":"...","title":"...","text":"..."}
                theme 是這篇文章的主題；title 是 30 字以內的標題；text 是完整的日文文章本文。
                目標 JLPT 等級：\(levelList)。
                \(levelGuidance)
                全文 400~700 字，內容要自然、生活化，使用「です/ます」體。
                文章中請刻意包含目標等級的字彙與文法點，讓學習者能從中擷取單字卡。
                文章裡頭不要夾帶英文註解、羅馬拼音或翻譯。
                """),
                .init(role: "user", content: """
                請寫一篇日文文章，主題：\(resolvedTheme)
                目標 JLPT 等級：\(levelList)
                """)
            ],
            temperature: 0.7
        )
    }

    public static func decodeCards(from content: String, sourceURL: URL) throws -> [LearningCard] {
        let cleaned = stripMarkdownFence(content)
        let data = Data(cleaned.utf8)
        let payload = try JSONDecoder().decode(CardPayload.self, from: data)
        return payload.cards.map {
            let jlptLevel = JLPTLevel(rawValue: $0.jlptLevel ?? "") ?? .unknown
            let verbFormType = VerbFormType(rawValue: $0.verbFormType ?? "") ?? .unknown
            return LearningCard(
                word: $0.word,
                reading: $0.reading,
                partOfSpeech: $0.partOfSpeech,
                meaningZh: $0.meaningZh,
                grammarNoteZh: $0.grammarNoteZh,
                jlptLevel: jlptLevel,
                verbFormType: verbFormType,
                exampleJa: $0.exampleJa,
                exampleReading: $0.exampleReading ?? "",
                exampleZh: $0.exampleZh,
                sourceUrl: sourceURL
            )
        }.filter {
            $0.jlptLevel != .n5
        }
    }

    public static func decodeQuiz(from content: String, cards: [LearningCard]) throws -> [QuizQuestion] {
        let cleaned = stripMarkdownFence(content)
        let data = Data(cleaned.utf8)
        let payload = try JSONDecoder().decode(QuizPayload.self, from: data)
        return payload.quizzes.compactMap { item in
            let choices = item.choices.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard choices.count == 4, choices.contains(item.correctAnswer) else {
                return nil
            }
            let cardId = item.cardId.flatMap(UUID.init(uuidString:))
            let matchedCardId = cardId ?? cards.first(where: { $0.word == item.sourceWord })?.id
            return QuizQuestion(
                cardId: matchedCardId,
                sourceWord: item.sourceWord,
                question: item.question,
                choices: choices,
                correctAnswer: item.correctAnswer,
                explanationZh: item.explanationZh
            )
        }
    }

    public static func decodeExampleReading(from content: String) throws -> String {
        let cleaned = stripMarkdownFence(content)
        let data = Data(cleaned.utf8)
        let payload = try JSONDecoder().decode(ExampleReadingPayload.self, from: data)
        return payload.exampleReading.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decodeArticle(from content: String, fallbackTheme: String) throws -> AIArticleDraft {
        let cleaned = stripMarkdownFence(content)
        let data = Data(cleaned.utf8)
        let payload = try JSONDecoder().decode(ArticlePayload.self, from: data)
        let theme = payload.theme.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw LLMClientError.noContent
        }
        let resolvedTheme = theme.isEmpty ? fallbackTheme : theme
        let resolvedTitle = title.isEmpty ? resolvedTheme : title
        return AIArticleDraft(
            theme: resolvedTheme,
            title: resolvedTitle,
            text: text
        )
    }

    private static func stripMarkdownFence(_ content: String) -> String {
        content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ChatCompletionRequest: Codable, Equatable, Sendable {
    public struct Message: Codable, Equatable, Sendable {
        public var role: String
        public var content: String
    }

    public var model: String
    public var messages: [Message]
    public var temperature: Double
}

private struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            var content: String
        }

        var message: Message
    }

    var choices: [Choice]
}

private struct ModelsResponse: Codable {
    struct Model: Codable {
        var id: String
    }

    var data: [Model]
}

private struct CardPayload: Codable {
    struct Card: Codable {
        var word: String
        var reading: String
        var partOfSpeech: String
        var meaningZh: String
        var grammarNoteZh: String
        var jlptLevel: String?
        var verbFormType: String?
        var exampleJa: String
        var exampleReading: String?
        var exampleZh: String
    }

    var cards: [Card]
}

private struct QuizPayload: Codable {
    struct Quiz: Codable {
        var cardId: String?
        var sourceWord: String
        var question: String
        var choices: [String]
        var correctAnswer: String
        var explanationZh: String
    }

    var quizzes: [Quiz]
}

private struct ExampleReadingPayload: Codable {
    var exampleReading: String
}

private struct ArticlePayload: Codable {
    var theme: String
    var title: String
    var text: String
}
