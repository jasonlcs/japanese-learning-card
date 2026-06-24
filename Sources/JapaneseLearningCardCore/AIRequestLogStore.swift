import Foundation

public enum AITraceContext {
    @TaskLocal public static var traceId: String?
    @TaskLocal public static var flow: String?
}

public struct AIRequestLogEntry: Codable, Sendable {
    public var timestamp: Date
    public var traceId: String?
    public var flow: String?
    public var event: String
    public var operation: String?
    public var message: String?
    public var endpoint: String?
    public var requestMethod: String?
    public var requestHeaders: [String: String]?
    public var requestBody: String?
    public var responseBody: String?
    public var input: [String: String]?
    public var output: [String: String]?
    public var model: String?
    public var statusCode: Int?
    public var durationMilliseconds: Int?
    public var requestBytes: Int?
    public var responseBytes: Int?
    public var timeoutSeconds: Int?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var bytesPerSecond: Double?
    public var tokensPerSecond: Double?
    public var errorSummary: String?

    public init(
        timestamp: Date = Date(),
        traceId: String? = AITraceContext.traceId,
        flow: String? = AITraceContext.flow,
        event: String,
        operation: String? = nil,
        message: String? = nil,
        endpoint: String? = nil,
        requestMethod: String? = nil,
        requestHeaders: [String: String]? = nil,
        requestBody: String? = nil,
        responseBody: String? = nil,
        input: [String: String]? = nil,
        output: [String: String]? = nil,
        model: String? = nil,
        statusCode: Int? = nil,
        durationMilliseconds: Int? = nil,
        requestBytes: Int? = nil,
        responseBytes: Int? = nil,
        timeoutSeconds: Int? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        bytesPerSecond: Double? = nil,
        tokensPerSecond: Double? = nil,
        errorSummary: String? = nil
    ) {
        self.timestamp = timestamp
        self.traceId = traceId
        self.flow = flow
        self.event = event
        self.operation = operation
        self.message = message
        self.endpoint = endpoint
        self.requestMethod = requestMethod
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.input = input
        self.output = output
        self.model = model
        self.statusCode = statusCode
        self.durationMilliseconds = durationMilliseconds
        self.requestBytes = requestBytes
        self.responseBytes = responseBytes
        self.timeoutSeconds = timeoutSeconds
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.bytesPerSecond = bytesPerSecond
        self.tokensPerSecond = tokensPerSecond
        self.errorSummary = errorSummary
    }
}

public actor AIRequestLogStore {
    public static let shared = AIRequestLogStore()

    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public nonisolated static var logFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("JapaneseLearningCard", isDirectory: true)
            .appendingPathComponent("ai-requests.jsonl")
    }

    @discardableResult
    public func ensureLogFile() throws -> URL {
        let url = Self.logFileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return url
    }

    public func append(_ entry: AIRequestLogEntry) {
        do {
            let url = try ensureLogFile()
            var data = try encoder.encode(entry)
            data.append(0x0A)
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            FileHandle.standardError.write(Data(("[LLM] 無法寫入 AI request log：\(error.localizedDescription)\n").utf8))
        }
    }

    public func appendEvent(
        _ event: String,
        operation: String? = nil,
        message: String? = nil,
        input: [String: String]? = nil,
        output: [String: String]? = nil,
        durationMilliseconds: Int? = nil,
        errorSummary: String? = nil
    ) {
        append(AIRequestLogEntry(
            event: event,
            operation: operation,
            message: message,
            input: input,
            output: output,
            durationMilliseconds: durationMilliseconds,
            errorSummary: errorSummary
        ))
    }
}
