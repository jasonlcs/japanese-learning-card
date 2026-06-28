import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 單一來源連線診斷的結果。提供「人看得懂的中文結論 + 技術細節 + 建議動作」，
/// 讓使用者能判斷『來源不能連』的真正原因（DNS、逾時、被站方阻擋、需瀏覽器渲染…）。
public struct SourceDiagnostic: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        /// 連得到且內容足夠，可正常擷取卡片。
        case ok
        /// 連得到但 URLSession 取到的文字過少，需靠瀏覽器渲染（JS 動態網站）。
        case needsBrowser
        /// 被站方阻擋（403/429），通常是 User-Agent／反爬蟲防護。
        case blocked
        /// 伺服器錯誤（5xx）。
        case serverError
        /// 其他用戶端錯誤（4xx，如 404）。
        case clientError
        /// DNS 解析失敗，找不到主機。
        case dnsFailure
        /// 連線逾時。
        case timeout
        /// 裝置目前沒有網路。
        case offline
        /// TLS／憑證錯誤。
        case tlsError
        /// 網址驗證未過（scheme／host／被封鎖位址）。
        case invalidURL
        /// 無法歸類的其他錯誤。
        case unknown
    }

    public var outcome: Outcome
    public var httpStatus: Int?
    public var latencyMs: Int?
    public var contentBytes: Int?
    public var usableTextCharacters: Int?
    /// 一句話結論（中文）。
    public var summary: String
    /// 技術細節（可選，供進階排查）。
    public var detail: String?
    /// 建議動作（中文）。
    public var suggestion: String?
    public var checkedAt: Date
    /// AI 解析測試結果：實際呼叫 provider 後解析出的卡片數；nil 表示未跑 AI 測試。
    public var aiParsedCardCount: Int?
    /// AI 解析測試的錯誤訊息；nil 表示沒測或沒出錯。
    public var aiParseError: String?
    /// AI 解析測試時內容與 DB 既有文件相同，未重複建立卡片。
    public var aiParseDuplicate: Bool

    public init(
        outcome: Outcome,
        httpStatus: Int? = nil,
        latencyMs: Int? = nil,
        contentBytes: Int? = nil,
        usableTextCharacters: Int? = nil,
        summary: String,
        detail: String? = nil,
        suggestion: String? = nil,
        checkedAt: Date = Date(),
        aiParsedCardCount: Int? = nil,
        aiParseError: String? = nil,
        aiParseDuplicate: Bool = false
    ) {
        self.outcome = outcome
        self.httpStatus = httpStatus
        self.latencyMs = latencyMs
        self.contentBytes = contentBytes
        self.usableTextCharacters = usableTextCharacters
        self.summary = summary
        self.detail = detail
        self.suggestion = suggestion
        self.checkedAt = checkedAt
        self.aiParsedCardCount = aiParsedCardCount
        self.aiParseError = aiParseError
        self.aiParseDuplicate = aiParseDuplicate
    }

    /// 是否表示來源目前可用（含「需瀏覽器渲染」，因為 app 會自動退回 WebKit）。
    public var isReachable: Bool {
        outcome == .ok || outcome == .needsBrowser
    }

    /// AI 解析測試的一句話結論；未跑 AI 測試時回傳 nil。
    public var aiParseSummary: String? {
        if let error = aiParseError {
            return "AI 解析失敗：\(error)"
        }
        if aiParseDuplicate {
            return "內容與既有資料相同，未重複建立卡片。"
        }
        if let count = aiParsedCardCount {
            return count == 0 ? "AI 這次沒解析出任何卡片。" : "AI 成功解析出 \(count) 張卡片並加入資料庫。"
        }
        return nil
    }

    /// 適合寫回 `Source.lastError` 的字串；可用時回傳 nil。
    /// 連線可用但 AI 解析出錯時，回傳 AI 的錯誤訊息(這也是來源實際不可用的原因)。
    public var errorMessageForSource: String? {
        if !isReachable { return summary }
        if let error = aiParseError { return "AI 解析失敗：\(error)" }
        return nil
    }
}

/// 對單一來源網址做分層連線診斷。
///
/// 與 `WebCrawler` 共用 `SourceValidator` 與 `HTMLTextExtractor`，但獨立出來以便
/// 在不真正寫入資料的情況下「驗證」來源，並把 `URLError` 等代碼翻譯成可行動的中文說明。
/// 當 app 的 User-Agent 拿到 403/429 時，會改用瀏覽器 UA 重試，藉此分辨
/// 「整個站連不上」與「只是 app 的 UA 被擋」。
public struct SourceConnectionTester: Sendable {
    /// 模擬一般瀏覽器的 User-Agent，僅在診斷重試時使用，用來判斷站方是否針對 UA 阻擋。
    public static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let validator: SourceValidator
    private let extractor: HTMLTextExtractor
    private let session: URLSession
    private let minimumUsefulCharacters: Int

    public init(
        validator: SourceValidator = SourceValidator(),
        extractor: HTMLTextExtractor = HTMLTextExtractor(),
        session: URLSession = SourceConnectionTester.makeDefaultSession(),
        minimumUsefulCharacters: Int = 800
    ) {
        self.validator = validator
        self.extractor = extractor
        self.session = session
        self.minimumUsefulCharacters = minimumUsefulCharacters
    }

    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    public func test(url: URL) async -> SourceDiagnostic {
        // 1) 先做與實際爬取相同的網址驗證。
        do {
            try validator.validate(url)
        } catch let error as SourceValidationError {
            return Self.diagnoseValidation(error)
        } catch {
            return SourceDiagnostic(
                outcome: .invalidURL,
                summary: "網址無法驗證：\(error.localizedDescription)",
                suggestion: "請確認網址格式正確（需以 http:// 或 https:// 開頭）。"
            )
        }

        // 2) 以 app 的 User-Agent 實際請求。
        let appResult = await fetch(url: url, userAgent: WebCrawler.userAgent)
        switch appResult {
        case .failure(let error):
            return Self.diagnoseTransport(error, host: url.host)
        case .success(let probe):
            let status = probe.statusCode
            if (200..<300).contains(status) {
                return diagnoseSuccess(probe)
            }
            if status == 403 || status == 429 {
                // app UA 被擋：用瀏覽器 UA 重試，分辨是站方反爬蟲還是整站不可用。
                return await diagnoseBlocked(url: url, appStatus: status, appLatencyMs: probe.latencyMs)
            }
            if (500..<600).contains(status) {
                return SourceDiagnostic(
                    outcome: .serverError,
                    httpStatus: status,
                    latencyMs: probe.latencyMs,
                    summary: "對方伺服器發生錯誤（HTTP \(status)）。",
                    detail: "Host：\(url.host ?? "?")",
                    suggestion: "通常是來源網站暫時故障，稍後再試；若持續發生請改用其他來源。"
                )
            }
            return SourceDiagnostic(
                outcome: .clientError,
                httpStatus: status,
                latencyMs: probe.latencyMs,
                summary: "請求被拒絕（HTTP \(status)）。",
                detail: "Host：\(url.host ?? "?")",
                suggestion: status == 404
                    ? "頁面可能已移除或網址錯誤，請確認連結是否仍有效。"
                    : "請確認此網址是否需要登入或有其他存取限制。"
            )
        }
    }

    // MARK: - 成功 / 內容判斷

    private func diagnoseSuccess(_ probe: Probe) -> SourceDiagnostic {
        let html = String(decoding: probe.data, as: UTF8.self)
        let extracted = extractor.extract(html: html)
        let usable = extracted.text.count
        if usable >= minimumUsefulCharacters {
            return SourceDiagnostic(
                outcome: .ok,
                httpStatus: probe.statusCode,
                latencyMs: probe.latencyMs,
                contentBytes: probe.data.count,
                usableTextCharacters: usable,
                summary: "連線正常，可擷取約 \(usable) 字內容。",
                detail: "HTTP \(probe.statusCode)、\(probe.data.count) bytes、\(probe.latencyMs) ms",
                suggestion: nil
            )
        }
        return SourceDiagnostic(
            outcome: .needsBrowser,
            httpStatus: probe.statusCode,
            latencyMs: probe.latencyMs,
            contentBytes: probe.data.count,
            usableTextCharacters: usable,
            summary: "連得到，但直接抓到的文字過少（\(usable) 字），可能是需要 JavaScript 載入的動態網站。",
            detail: "HTTP \(probe.statusCode)、\(probe.data.count) bytes、可用文字 \(usable) 字",
            suggestion: "App 會自動改用內建瀏覽器渲染後再擷取；若仍抓不到內容，建議改用提供完整文章 HTML 的來源。"
        )
    }

    // MARK: - 403 / 429 阻擋判斷

    private func diagnoseBlocked(url: URL, appStatus: Int, appLatencyMs: Int) async -> SourceDiagnostic {
        let browserResult = await fetch(url: url, userAgent: Self.browserUserAgent)
        if case .success(let probe) = browserResult, (200..<300).contains(probe.statusCode) {
            return SourceDiagnostic(
                outcome: .blocked,
                httpStatus: appStatus,
                latencyMs: appLatencyMs,
                summary: "此網站擋掉了 App 的連線（HTTP \(appStatus)），但用一般瀏覽器可以開啟。",
                detail: "App UA 回 \(appStatus)；瀏覽器 UA 回 \(probe.statusCode)。判定為站方針對 User-Agent／反爬蟲阻擋。",
                suggestion: "這類來源（如部分新聞網站）會阻擋自動程式抓取，較不適合作為來源；可改用允許程式存取的網站，或改用 AI 生成文章。"
            )
        }
        return SourceDiagnostic(
            outcome: .blocked,
            httpStatus: appStatus,
            latencyMs: appLatencyMs,
            summary: "被網站阻擋（HTTP \(appStatus)）。",
            detail: "App UA 與瀏覽器 UA 皆無法正常取得內容，可能有反爬蟲或地區／登入限制。",
            suggestion: "此來源不適合自動擷取，建議改用其他網站或 AI 生成文章。"
        )
    }

    // MARK: - 驗證錯誤翻譯

    private static func diagnoseValidation(_ error: SourceValidationError) -> SourceDiagnostic {
        switch error {
        case .unsupportedScheme:
            return SourceDiagnostic(
                outcome: .invalidURL,
                summary: "只支援 http:// 或 https:// 的網址。",
                suggestion: "請貼上完整網址，並確認開頭是 http:// 或 https://。"
            )
        case .missingHost:
            return SourceDiagnostic(
                outcome: .invalidURL,
                summary: "網址缺少主機名稱。",
                suggestion: "請確認網址完整，例如 https://example.com/article。"
            )
        case .blockedHost(let host):
            return SourceDiagnostic(
                outcome: .invalidURL,
                summary: "此主機被封鎖（內部／私有位址）：\(host)。",
                suggestion: "基於安全考量無法連線內部或私有網段的位址，請使用公開網站。"
            )
        }
    }

    // MARK: - 傳輸錯誤翻譯

    private static func diagnoseTransport(_ error: Error, host: String?) -> SourceDiagnostic {
        let hostLabel = host.map { "Host：\($0)" }
        guard let urlError = error as? URLError else {
            return SourceDiagnostic(
                outcome: .unknown,
                summary: "連線失敗：\(error.localizedDescription)",
                detail: hostLabel,
                suggestion: "請稍後再試；若持續失敗請改用其他來源。"
            )
        }

        switch urlError.code {
        case .timedOut:
            return SourceDiagnostic(
                outcome: .timeout,
                summary: "連線逾時，對方在時間內沒有回應。",
                detail: hostLabel,
                suggestion: "可能是網站太慢或網路不穩，稍後再試；若每次都逾時，建議改用其他來源。"
            )
        case .cannotFindHost, .dnsLookupFailed:
            return SourceDiagnostic(
                outcome: .dnsFailure,
                summary: "找不到主機，DNS 解析失敗。",
                detail: hostLabel,
                suggestion: "請確認網址拼寫正確、網站仍存在，並檢查網路／DNS 設定。"
            )
        case .cannotConnectToHost:
            return SourceDiagnostic(
                outcome: .dnsFailure,
                summary: "無法連上主機（對方拒絕或沒有服務在該埠）。",
                detail: hostLabel,
                suggestion: "請確認網站目前是否正常運作，或稍後再試。"
            )
        case .notConnectedToInternet, .networkConnectionLost, .internationalRoamingOff, .dataNotAllowed:
            return SourceDiagnostic(
                outcome: .offline,
                summary: "目前沒有網路連線。",
                detail: hostLabel,
                suggestion: "請檢查裝置的網路連線後再試一次。"
            )
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired:
            return SourceDiagnostic(
                outcome: .tlsError,
                summary: "HTTPS／憑證驗證失敗。",
                detail: hostLabel,
                suggestion: "對方網站的安全憑證有問題；請確認網址是否正確，或改用其他來源。"
            )
        case .unsupportedURL, .badURL:
            return SourceDiagnostic(
                outcome: .invalidURL,
                summary: "網址格式不正確。",
                detail: hostLabel,
                suggestion: "請確認網址完整且以 http:// 或 https:// 開頭。"
            )
        default:
            return SourceDiagnostic(
                outcome: .unknown,
                summary: "連線失敗：\(urlError.localizedDescription)",
                detail: (hostLabel.map { $0 + "，" } ?? "") + "URLError code \(urlError.errorCode)",
                suggestion: "請稍後再試；若持續失敗請改用其他來源。"
            )
        }
    }

    // MARK: - 請求

    private struct Probe {
        var statusCode: Int
        var data: Data
        var latencyMs: Int
    }

    private func fetch(url: URL, userAgent: String) async -> Result<Probe, Error> {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpMethod = "GET"
        let startedAt = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let latencyMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return .success(Probe(statusCode: status, data: data, latencyMs: latencyMs))
        } catch {
            return .failure(error)
        }
    }
}
