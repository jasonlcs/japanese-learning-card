import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum LLMClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(code: Int, body: String)
    case decodingFailed(detail: String, raw: String)
    case noContent

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Missing API key."
        case .invalidResponse:
            "The provider returned an invalid response."
        case .httpStatus(let code, let body):
            body.isEmpty ? "Provider returned HTTP \(code)." : "Provider returned HTTP \(code): \(body)"
        case .decodingFailed(let detail, let raw):
            "無法解析模型回應(\(detail))。原始內容：\(raw)"
        case .noContent:
            "The provider returned no content."
        }
    }
}

public protocol LLMClient: Sendable {
    func generateCards(document: CrawledDocument, sourcePrompt: String, settings: AppSettings) async throws -> [LearningCard]
    func generateQuiz(cards: [LearningCard], settings: AppSettings) async throws -> [QuizQuestion]
    func generateArticle(theme: String, jlptLevels: [JLPTLevel], settings: AppSettings) async throws -> AIArticleDraft
    /// 由使用者貼上的文字（文章或單字清單）直接產生學習卡。
    func generateManualCards(text: String, instruction: String, sourceURL: URL, settings: AppSettings) async throws -> [LearningCard]
}

public extension LLMClient {
    /// 預設實作：沿用一般的擷取流程，方便測試替身或其他 client 直接套用。
    func generateManualCards(text: String, instruction: String, sourceURL: URL, settings: AppSettings) async throws -> [LearningCard] {
        let document = CrawledDocument(
            sourceId: AISource.sentinelSourceId,
            url: sourceURL,
            title: "手動輸入",
            plainText: text,
            contentHash: ContentHash.sha256(text)
        )
        let prompt = instruction.isEmpty ? "請從以下內容挑出值得學習的日文單字與片語。" : instruction
        return try await generateCards(document: document, sourcePrompt: prompt, settings: settings)
    }
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
    public static let userAgent = "JapaneseLearningCard/0.1 (+https://github.com/jasonlcs/japanese-learning-card)"
    private static let providerRequestTimeout: TimeInterval = 180
    private static let providerResourceTimeout: TimeInterval = 240

    private let secretStore: SecretStore
    private let session: URLSession

    public init(secretStore: SecretStore = KeychainStore(), session: URLSession = OpenAICompatibleLLMClient.makeDefaultSession()) {
        self.secretStore = secretStore
        self.session = session
    }

    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = providerRequestTimeout
        config.timeoutIntervalForResource = providerResourceTimeout
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

        let data = try await performLoggedRequest(request, operation: "generateCards", model: settings.providerConfig.model)
        Self.debugLog("回應原始 body：\n\(String(decoding: data, as: UTF8.self))")
        let content = try Self.extractContent(from: data)
        let cards = try Self.decodeCards(from: content, sourceURL: document.url)
        await AIRequestLogStore.shared.appendEvent(
            "llm.decode.completed",
            operation: "generateCards",
            output: [
                "sourceURL": document.url.absoluteString,
                "cardCount": "\(cards.count)"
            ]
        )
        return cards
    }

    public func generateManualCards(text: String, instruction: String, sourceURL: URL, settings: AppSettings) async throws -> [LearningCard] {
        guard let apiKey = try secretStore.apiKey(reference: settings.providerConfig.apiKeyKeychainRef), !apiKey.isEmpty else {
            throw LLMClientError.missingAPIKey
        }

        let body = Self.manualCardsRequestBody(text: text, instruction: instruction, settings: settings)
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

        let data = try await performLoggedRequest(request, operation: "generateManualCards", model: settings.providerConfig.model)
        Self.debugLog("回應原始 body：\n\(String(decoding: data, as: UTF8.self))")
        let content = try Self.extractContent(from: data)
        let cards = try Self.decodeCards(from: content, sourceURL: sourceURL, includeN5: true)
        await AIRequestLogStore.shared.appendEvent(
            "llm.decode.completed",
            operation: "generateManualCards",
            output: [
                "sourceURL": sourceURL.absoluteString,
                "cardCount": "\(cards.count)"
            ]
        )
        return cards
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

        let data = try await performLoggedRequest(request, operation: "generateQuiz", model: settings.providerConfig.model)
        Self.debugLog("回應原始 body：\n\(String(decoding: data, as: UTF8.self))")
        let content = try Self.extractContent(from: data)
        let quizzes = try Self.decodeQuiz(from: content, cards: cards)
        await AIRequestLogStore.shared.appendEvent(
            "llm.decode.completed",
            operation: "generateQuiz",
            output: ["quizCount": "\(quizzes.count)"]
        )
        return quizzes
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
            temperature: 0.1,
            responseFormat: Self.responseFormat(for: settings)
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

        let data = try await performLoggedRequest(request, operation: "generateExampleReading", model: settings.providerConfig.model)
        Self.debugLog("回應原始 body：\n\(String(decoding: data, as: UTF8.self))")
        let content = try Self.extractContent(from: data)
        let reading = try Self.decodeExampleReading(from: content)
        await AIRequestLogStore.shared.appendEvent(
            "llm.decode.completed",
            operation: "generateExampleReading",
            output: ["exampleReading": reading]
        )
        return reading
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

        Self.debugLog("article 請求 → \(request.url?.absoluteString ?? "")，model=\(settings.providerConfig.model)，levels=\(jlptLevels.map(\.rawValue).joined(separator: ","))")
        let data = try await performLoggedRequest(request, operation: "generateArticle", model: settings.providerConfig.model)
        Self.debugLog("article 回應原始 body：\n\(String(decoding: data, as: UTF8.self))")
        let content = try Self.extractContent(from: data)
        let draft = try Self.decodeArticle(from: content, fallbackTheme: theme)
        await AIRequestLogStore.shared.appendEvent(
            "llm.decode.completed",
            operation: "generateArticle",
            output: [
                "theme": draft.theme,
                "title": draft.title,
                "textCharacters": "\(draft.text.count)"
            ]
        )
        return draft
    }

    /// 解析 provider 的外層回應並取出 message.content；失敗時印出原始 body 方便除錯。
    private static func extractContent(from data: Data) throws -> String {
        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            let raw = String(decoding: data, as: UTF8.self)
            log("無法解析 provider 外層回應 (ChatCompletionResponse)：\(describeDecodingError(error))\n----- 原始 body 開始 -----\n\(raw)\n----- 原始 body 結束 -----")
            let snippet = raw.count > 400 ? String(raw.prefix(400)) + "…" : raw
            throw LLMClientError.decodingFailed(detail: describeDecodingError(error), raw: snippet)
        }
        guard let content = decoded.choices.first?.message.content else {
            throw LLMClientError.noContent
        }
        return content
    }

    public func listModels(settings: AppSettings, apiKeyOverride: String? = nil) async throws -> [String] {
        let apiKey: String
        if let apiKeyOverride, !apiKeyOverride.isEmpty {
            apiKey = apiKeyOverride
        } else {
            guard let stored = try secretStore.apiKey(reference: settings.providerConfig.apiKeyKeychainRef), !stored.isEmpty else {
                throw LLMClientError.missingAPIKey
            }
            apiKey = stored
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

        let data = try await performLoggedRequest(request, operation: "listModels", model: settings.providerConfig.model)

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let models = decoded.data.map(\.id).sorted()
        await AIRequestLogStore.shared.appendEvent(
            "llm.decode.completed",
            operation: "listModels",
            output: ["modelCount": "\(models.count)"]
        )
        return models
    }

    private func performLoggedRequest(_ request: URLRequest, operation: String, model: String) async throws -> Data {
        var request = request
        request.timeoutInterval = Self.providerRequestTimeout
        let startedAt = Date()
        let requestBytes = request.httpBody?.count ?? 0
        await Self.logRequestStart(
            operation: operation,
            request: request,
            model: model,
            requestBytes: requestBytes
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            await Self.logRequest(
                operation: operation,
                request: request,
                model: model,
                startedAt: startedAt,
                statusCode: nil,
                requestBytes: requestBytes,
                responseData: Data(),
                errorSummary: error.localizedDescription
            )
            throw error
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode
        let isHTTPError = statusCode.map { !(200..<300).contains($0) } ?? false
        await Self.logRequest(
            operation: operation,
            request: request,
            model: model,
            startedAt: startedAt,
            statusCode: statusCode,
            requestBytes: requestBytes,
            responseData: data,
            errorSummary: isHTTPError ? Self.responseSnippet(from: data) : nil
        )
        try Self.validateHTTPResponse(response, data: data)
        return data
    }

    /// 依 provider 設定決定是否要求結構化輸出。集中在一處，避免每個請求各寫一份。
    static func responseFormat(for settings: AppSettings) -> ChatCompletionRequest.ResponseFormat? {
        switch settings.providerConfig.structuredOutput {
        case .jsonObject: ChatCompletionRequest.ResponseFormat(type: "json_object")
        case .off: nil
        }
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
                請同時挑選「單字／片語」與「文法句型」。若來源文字有可學習的文法，至少產生 1 張文法卡；整體最多 6 張卡。
                \(allowedOutputWritingRules)
                \(cardLayoutContentRules)
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
            temperature: 0.4,
            responseFormat: responseFormat(for: settings)
        )
    }

    public static func manualCardsRequestBody(text: String, instruction: String, settings: AppSettings) -> ChatCompletionRequest {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let userInstruction = trimmedInstruction.isEmpty ? "（無額外指示）" : trimmedInstruction
        return ChatCompletionRequest(
            model: settings.providerConfig.model,
            messages: [
                .init(role: "system", content: """
                你是日文學習卡產生器。只輸出 JSON，不要 Markdown。
                JSON schema: {"cards":[{"word":"...","reading":"...","partOfSpeech":"...","meaningZh":"...","grammarNoteZh":"...","jlptLevel":"N1|N2|N3|N4|N5|Unknown","verbFormType":"一段動詞|五段動詞|する動詞|くる動詞|不規則動詞|非動詞|不明","exampleJa":"...","exampleReading":"...","exampleZh":"..."}]}
                使用者會貼上一段日文文章或一份單字／片語清單：
                - 若是文章，請挑出值得學習的重要單字與片語。
                - 若是單字／片語清單，請為清單中每個項目各產生一張卡，盡量不要遺漏。
                所有 JLPT 等級都要保留（包含 N5），請依實際難度標註 jlptLevel；無法判斷時用 Unknown。
                如果 partOfSpeech 是動詞，verbFormType 必須標註動詞型態；如果不是動詞，verbFormType 使用「非動詞」。
                exampleReading 是必填欄位，必須把 exampleJa 整句完整轉成平假名讀音；漢字必須轉成正確平假名，助詞保留原本讀音，不要使用羅馬拼音。
                exampleJa 請自然地造句示範該單字；若輸入本身就是完整句子可直接沿用。
                若內容是文章，請同時挑選「單字／片語」與「文法句型」；若有可學習的文法，至少產生 1 張文法卡。
                最多產生 30 張卡。
                \(allowedOutputWritingRules)
                \(cardLayoutContentRules)
                """),
                .init(role: "user", content: """
                使用者的額外指示：
                \(userInstruction)

                內容：
                \(String(text.prefix(12000)))
                """)
            ],
            temperature: 0.3,
            responseFormat: responseFormat(for: settings)
        )
    }

    private static let cardLayoutContentRules = """
    卡片內容必須符合以下版型規範：
    1. 單字／片語卡：
       - word 填單字或片語，不要加「〜」。
       - partOfSpeech 填精確品詞，例如「名詞」「他動詞」「副詞」「連語」。
       - grammarNoteZh 必須剛好使用下列標籤，每個標籤各一行，不可省略：
         重點：用繁體中文說明語感、常見搭配或使用注意。
         よく使う形：列出 2~3 個「包含此單字／片語的常見語形或搭配模板」，以「、」分隔。這不是使用場景，不要寫「會話中」「文章中」這類場合。名詞例：「〜の途中で、〜の途中に、〜している途中」；動詞例：「辞書形、て形、ない形」或常見搭配；形容詞例：「〜くなる、〜そうだ、〜すぎる」。
         関連語：列出 2~3 個近義詞、反義詞或關聯詞，以「、」分隔，並可用繁體中文括號補充差異。
    2. 文法句型卡：
       - word 必須用「〜」標示句型，例如「〜つつある」「〜に従って」。
       - reading 填平假名讀音或假名形式，例如「〜つつある」。
       - partOfSpeech 必須填「文法句型」。
       - verbFormType 必須填「非動詞」。
       - grammarNoteZh 必須剛好使用下列標籤，每個標籤各一行，不可省略：
         接續：寫出接續規則，例如「Vます形去ます + つつある」。
         重點：用繁體中文說明意思、語氣、使用限制。
         使用場景：列出 2~3 個常見使用場合，以「、」分隔。
         類似表現：列出 2~3 個相近句型並說明差異，例如「〜ている：狀態持續；〜はじめる：動作開始」。
    3. exampleJa 必須自然示範該 word，文法卡必須示範該句型；exampleZh 必須翻譯整句。
    """

    private static let allowedOutputWritingRules = """
    文字規則：
    - 中文欄位只能使用繁體中文，禁止簡體中文。
    - 可使用英文、日文平假名、片假名、日文漢字，以及必要的數字與標點。
    - 除非來源語句本身需要，避免混入其他語言；如需使用其他語言，只能少量出現在例子或補充說明。
    """

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
                \(allowedOutputWritingRules)
                """),
                .init(role: "user", content: """
                請根據以下學習卡產生最多 5 題選擇題：

                \(source)
                """)
            ],
            temperature: 0.35,
            responseFormat: responseFormat(for: settings)
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
                若需要中文欄位或說明，必須使用繁體中文，禁止簡體中文。
                """),
                .init(role: "user", content: """
                請寫一篇日文文章，主題：\(resolvedTheme)
                目標 JLPT 等級：\(levelList)
                """)
            ],
            temperature: 0.7,
            responseFormat: responseFormat(for: settings)
        )
    }

    public static func decodeCards(from content: String, sourceURL: URL, includeN5: Bool = false) throws -> [LearningCard] {
        let payload = try decodeJSON(CardPayload.self, from: content)
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
            includeN5 || $0.jlptLevel != .n5
        }
    }

    public static func decodeQuiz(from content: String, cards: [LearningCard]) throws -> [QuizQuestion] {
        let payload = try decodeJSON(QuizPayload.self, from: content)
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
        let payload = try decodeJSON(ExampleReadingPayload.self, from: content)
        return payload.exampleReading.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decodeArticle(from content: String, fallbackTheme: String) throws -> AIArticleDraft {
        let payload = try decodeJSON(ArticlePayload.self, from: content)
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

    /// 一律印到 stderr，方便 `swift run` 時直接在終端機看到。
    static func log(_ message: @autoclosure () -> String) {
        FileHandle.standardError.write(Data(("[LLM] " + message() + "\n").utf8))
    }

    /// 詳細請求/回應日誌，預設關閉；設 JLC_DEBUG_LLM=1 才會輸出。
    static func debugLog(_ message: @autoclosure () -> String) {
        guard ProcessInfo.processInfo.environment["JLC_DEBUG_LLM"] != nil else { return }
        log(message())
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else {
            return
        }
        let snippet = responseSnippet(from: data)
        throw LLMClientError.httpStatus(code: http.statusCode, body: snippet)
    }

    private static func responseSnippet(from data: Data) -> String {
        let body = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.count > 500 ? String(body.prefix(500)) + "…" : body
    }

    private static func logRequest(
        operation: String,
        request: URLRequest,
        model: String,
        startedAt: Date,
        statusCode: Int?,
        requestBytes: Int,
        responseData: Data,
        errorSummary: String?
    ) async {
        let duration = max(Date().timeIntervalSince(startedAt), 0.001)
        let usage = decodeUsage(from: responseData)
        let completionTokens = usage?.completionTokens
        let entry = AIRequestLogEntry(
            event: errorSummary == nil ? "llm.request.completed" : "llm.request.failed",
            operation: operation,
            endpoint: sanitizedEndpoint(for: request.url),
            requestMethod: request.httpMethod,
            requestHeaders: sanitizedHeaders(from: request),
            responseBody: bodyString(from: responseData),
            model: model,
            statusCode: statusCode,
            durationMilliseconds: Int((duration * 1000).rounded()),
            requestBytes: requestBytes,
            responseBytes: responseData.count,
            timeoutSeconds: Int(request.timeoutInterval.rounded()),
            promptTokens: usage?.promptTokens,
            completionTokens: completionTokens,
            totalTokens: usage?.totalTokens,
            bytesPerSecond: Double(responseData.count) / duration,
            tokensPerSecond: completionTokens.map { Double($0) / duration },
            errorSummary: errorSummary
        )
        await AIRequestLogStore.shared.append(entry)
    }

    private static func logRequestStart(
        operation: String,
        request: URLRequest,
        model: String,
        requestBytes: Int
    ) async {
        let entry = AIRequestLogEntry(
            event: "llm.request.start",
            operation: operation,
            endpoint: sanitizedEndpoint(for: request.url),
            requestMethod: request.httpMethod,
            requestHeaders: sanitizedHeaders(from: request),
            requestBody: bodyString(from: request.httpBody ?? Data()),
            model: model,
            requestBytes: requestBytes,
            timeoutSeconds: Int(request.timeoutInterval.rounded())
        )
        await AIRequestLogStore.shared.append(entry)
    }

    private static func sanitizedEndpoint(for url: URL?) -> String {
        guard let url else { return "" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private static func sanitizedHeaders(from request: URLRequest) -> [String: String] {
        let sensitiveHeaders = [
            "authorization",
            "proxy-authorization",
            "x-api-key",
            "api-key",
            "openai-organization",
            "openai-project"
        ]
        return (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { result, pair in
            if sensitiveHeaders.contains(pair.key.lowercased()) {
                result[pair.key] = "<redacted>"
            } else {
                result[pair.key] = pair.value
            }
        }
    }

    private static func bodyString(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let raw = String(decoding: data, as: UTF8.self)
        let maxCharacters = 200_000
        guard raw.count > maxCharacters else { return raw }
        return String(raw.prefix(maxCharacters)) + "\n...[truncated \(raw.count - maxCharacters) characters]"
    }

    private static func decodeUsage(from data: Data) -> ChatCompletionResponse.Usage? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(ChatCompletionResponse.self, from: data).usage
    }

    private static func stripMarkdownFence(_ content: String) -> String {
        content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 從模型回應中抽出最外層的 JSON 物件，容忍前後夾雜的說明文字、markdown
    /// 或推理型模型的 <think>…</think> 區塊。
    private static func extractJSONObject(_ content: String) -> String {
        let withoutThink = stripThinkBlocks(content)
        let cleaned = stripMarkdownFence(withoutThink)
        return balancedJSONObject(in: cleaned) ?? cleaned
    }

    /// 推理型模型(R1 / QwQ / deepseek 等)會在真正答案前輸出推理區塊，
    /// 其中常含有會干擾解析的大括號。泛化處理常見的推理結束標記，
    /// 取最後一個標記之後的內容作為真正的回答——新模型只要用同類標記即可自動相容。
    private static let reasoningCloseTags = ["</think>", "</thinking>", "</reasoning>", "</thought>"]

    private static func stripThinkBlocks(_ content: String) -> String {
        var cutIndex: String.Index?
        for tag in reasoningCloseTags {
            if let range = content.range(of: tag, options: [.backwards, .caseInsensitive]) {
                if cutIndex == nil || range.upperBound > cutIndex! {
                    cutIndex = range.upperBound
                }
            }
        }
        guard let cutIndex else { return content }
        return String(content[cutIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 從第一個 `{` 開始做大括號配對(忽略字串內的括號)，回傳第一個完整的 JSON 物件。
    private static func balancedJSONObject(in content: String) -> String? {
        guard let start = content.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < content.endIndex {
            let character = content[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(content[start...index])
                    }
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    private static func decodeJSON<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        let json = extractJSONObject(content)
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            // 解碼失敗一定把模型回的完整原文印出來，方便貼上來除錯。
            log("解碼 \(T.self) 失敗：\(describeDecodingError(error))\n----- 模型原始回應開始 -----\n\(content)\n----- 模型原始回應結束 -----")
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = trimmed.count > 400 ? String(trimmed.prefix(400)) + "…" : trimmed
            throw LLMClientError.decodingFailed(detail: describeDecodingError(error), raw: snippet)
        }
    }

    private static func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, _):
            return "缺少欄位「\(key.stringValue)」"
        case .typeMismatch(_, let context):
            return "型別不符：\(context.debugDescription)"
        case .valueNotFound(_, let context):
            return "缺少值：\(context.debugDescription)"
        case .dataCorrupted(let context):
            return "內容非合法 JSON：\(context.debugDescription)"
        @unknown default:
            return decodingError.localizedDescription
        }
    }
}

public struct ChatCompletionRequest: Codable, Equatable, Sendable {
    public struct Message: Codable, Equatable, Sendable {
        public var role: String
        public var content: String
    }

    public struct ResponseFormat: Codable, Equatable, Sendable {
        public var type: String
        public init(type: String) { self.type = type }
    }

    public var model: String
    public var messages: [Message]
    public var temperature: Double
    /// 對應 OpenAI 的 response_format；nil 時不送出此欄位(相容不支援的 endpoint)。
    public var responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
    }

    public init(model: String, messages: [Message], temperature: Double, responseFormat: ResponseFormat? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.responseFormat = responseFormat
    }
}

private struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            var content: String
        }

        var message: Message
    }

    struct Usage: Codable {
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    var choices: [Choice]
    var usage: Usage?
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
