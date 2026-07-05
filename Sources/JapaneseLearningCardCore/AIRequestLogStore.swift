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
    public var startedAt: Date?
    public var finishedAt: Date?

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
        errorSummary: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil
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
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

public actor AIRequestLogStore {
    public static let shared = AIRequestLogStore()

    private let encoder: JSONEncoder
    private nonisolated let directory: URL
    /// ai-latest.log 目前鏡射的 traceId；只有 flow.start 會切換，
    /// 避免並行執行的舊流程尾段把最新流程的檔案洗掉。
    private var latestTraceId: String?

    public init(directory: URL? = nil) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.directory = directory ?? AppPaths.appSupportFolder
    }

    public nonisolated static var logFileURL: URL {
        AppPaths.appSupportFolder
            .appendingPathComponent("ai-requests.jsonl")
    }

    public nonisolated static var latestLogFileURL: URL {
        AppPaths.appSupportFolder
            .appendingPathComponent("ai-latest.log")
    }

    public nonisolated var logFileURL: URL {
        directory.appendingPathComponent("ai-requests.jsonl")
    }

    public nonisolated var latestLogFileURL: URL {
        directory.appendingPathComponent("ai-latest.log")
    }

    @discardableResult
    public func ensureLogFile() throws -> URL {
        let url = logFileURL
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
            try appendData(data, to: url)
            try mirrorToLatestLog(entry, data: data)
        } catch {
            FileHandle.standardError.write(Data(("[LLM] 無法寫入 AI request log：\(error.localizedDescription)\n").utf8))
        }
    }

    /// 記錄流程事件。傳入 `startedAt` 時會自動補上 `finishedAt`（＝寫入當下）
    /// 與 `durationMilliseconds`，讓 flow 結尾事件帶有完整起迄時間。
    public func appendEvent(
        _ event: String,
        operation: String? = nil,
        message: String? = nil,
        input: [String: String]? = nil,
        output: [String: String]? = nil,
        startedAt: Date? = nil,
        durationMilliseconds: Int? = nil,
        errorSummary: String? = nil
    ) {
        let now = Date()
        var duration = durationMilliseconds
        if duration == nil, let startedAt {
            duration = Int(now.timeIntervalSince(startedAt) * 1000)
        }
        append(AIRequestLogEntry(
            timestamp: now,
            event: event,
            operation: operation,
            message: message,
            input: input,
            output: output,
            durationMilliseconds: duration,
            errorSummary: errorSummary,
            startedAt: startedAt,
            finishedAt: startedAt != nil ? now : nil
        ))
    }

    private func appendData(_ data: Data, to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// ai-latest.log 只保留最近一次啟動的流程：看到 flow.start（或啟動後第一筆
    /// 有 traceId 的事件）就重置檔案，之後只鏡射同一 traceId 的事件。
    private func mirrorToLatestLog(_ entry: AIRequestLogEntry, data: Data) throws {
        guard let traceId = entry.traceId else { return }
        if entry.event == "flow.start" || latestTraceId == nil {
            latestTraceId = traceId
            FileManager.default.createFile(atPath: latestLogFileURL.path, contents: nil)
        }
        guard traceId == latestTraceId else { return }
        try appendData(data, to: latestLogFileURL)
    }
}
