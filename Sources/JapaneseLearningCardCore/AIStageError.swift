import Foundation

/// 把 AI 流程的錯誤標上「發生在哪個階段」，讓 UI 與 log 都能直接看出
/// 是網頁抓取、AI 模型請求，還是回應解析出了問題，而不是一句籠統的 timeout。
public struct AIStageError: LocalizedError, Sendable {
    public enum Stage: String, Sendable {
        case webCrawl
        case aiRequest
        case aiDecode

        public var label: String {
            switch self {
            case .webCrawl: "網頁抓取"
            case .aiRequest: "AI 模型請求"
            case .aiDecode: "AI 回應解析"
            }
        }
    }

    public var stage: Stage
    public var operation: String
    public var detail: String

    public init(stage: Stage, operation: String, detail: String) {
        self.stage = stage
        self.operation = operation
        self.detail = detail
    }

    public var errorDescription: String? {
        "【\(stage.label)階段失敗】\(operation)：\(detail)"
    }

    /// 已經標過階段的錯誤原樣保留，其他錯誤補上階段標籤。
    public static func wrap(_ error: Error, stage: Stage, operation: String) -> Error {
        if error is AIStageError { return error }
        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return AIStageError(stage: stage, operation: operation, detail: detail)
    }
}
