import Foundation

public struct AIRequestLogEntry: Codable, Sendable {
    public var timestamp: Date
    public var operation: String
    public var endpoint: String
    public var model: String
    public var statusCode: Int?
    public var durationMilliseconds: Int
    public var requestBytes: Int
    public var responseBytes: Int
    public var timeoutSeconds: Int
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var bytesPerSecond: Double
    public var tokensPerSecond: Double?
    public var errorSummary: String?

    public init(
        timestamp: Date = Date(),
        operation: String,
        endpoint: String,
        model: String,
        statusCode: Int?,
        durationMilliseconds: Int,
        requestBytes: Int,
        responseBytes: Int,
        timeoutSeconds: Int,
        promptTokens: Int?,
        completionTokens: Int?,
        totalTokens: Int?,
        bytesPerSecond: Double,
        tokensPerSecond: Double?,
        errorSummary: String?
    ) {
        self.timestamp = timestamp
        self.operation = operation
        self.endpoint = endpoint
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
}
