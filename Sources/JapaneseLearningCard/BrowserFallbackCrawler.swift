import Foundation
import JapaneseLearningCardCore
import WebKit

struct BrowserFallbackCrawler: Crawling {
    private let primary = WebCrawler()
    private let rendered = WebViewRenderedCrawler()
    private let minimumUsefulCharacters = 800

    func crawl(source: Source) async throws -> CrawledDocument {
        do {
            let document = try await primary.crawl(source: source)
            if document.plainText.count >= minimumUsefulCharacters {
                await AIRequestLogStore.shared.appendEvent(
                    "crawler.completed",
                    operation: "urlSessionCrawl",
                    input: ["sourceURL": source.url.absoluteString],
                    output: [
                        "strategy": "urlSession",
                        "plainTextCharacters": "\(document.plainText.count)"
                    ]
                )
                return document
            }

            await AIRequestLogStore.shared.appendEvent(
                "crawler.fallback",
                operation: "webViewCrawl",
                message: "URLSession crawler returned short text; retrying with WebKit-rendered page.",
                input: ["sourceURL": source.url.absoluteString],
                output: ["urlSessionCharacters": "\(document.plainText.count)"]
            )
        } catch {
            await AIRequestLogStore.shared.appendEvent(
                "crawler.fallback",
                operation: "webViewCrawl",
                message: "URLSession crawler failed; retrying with WebKit-rendered page.",
                input: ["sourceURL": source.url.absoluteString],
                errorSummary: error.localizedDescription
            )
        }

        return try await rendered.crawl(source: source)
    }
}

private enum WebViewRenderedCrawlerError: LocalizedError {
    case timeout
    case emptyBodyText

    var errorDescription: String? {
        switch self {
        case .timeout:
            "Browser-rendered crawl timed out."
        case .emptyBodyText:
            "Browser-rendered page did not expose readable text."
        }
    }
}

final class WebViewRenderedCrawler: NSObject, Crawling, @unchecked Sendable {
    private let timeoutSeconds: TimeInterval = 20

    func crawl(source: Source) async throws -> CrawledDocument {
        try SourceValidator().validate(source.url)
        return try await render(source: source)
    }

    @MainActor
    private func render(source: Source) async throws -> CrawledDocument {
        let startedAt = Date()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let observer = WebViewLoadObserver(timeoutSeconds: timeoutSeconds)
        webView.navigationDelegate = observer
        webView.load(URLRequest(url: source.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutSeconds))

        try await observer.waitForLoad()
        try await Task.sleep(nanoseconds: 800_000_000)

        let title = try await evaluateString("document.title || ''", in: webView)
        let text = try await evaluateString("document.body ? document.body.innerText : ''", in: webView)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !text.isEmpty else {
            throw WebViewRenderedCrawlerError.emptyBodyText
        }
        guard text.utf8.count <= WebCrawler.maxPayloadBytes else {
            throw WebCrawlerError.payloadTooLarge
        }

        let document = CrawledDocument(
            sourceId: source.id,
            url: source.url,
            title: title,
            plainText: text,
            contentHash: ContentHash.sha256(text)
        )

        await AIRequestLogStore.shared.appendEvent(
            "crawler.completed",
            operation: "webViewCrawl",
            input: ["sourceURL": source.url.absoluteString],
            output: [
                "strategy": "webView",
                "title": title,
                "plainTextCharacters": "\(text.count)"
            ],
            durationMilliseconds: Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        )
        return document
    }

    @MainActor
    private func evaluateString(_ javaScript: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(javaScript) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }
}

@MainActor
private final class WebViewLoadObserver: NSObject, WKNavigationDelegate {
    private let timeoutSeconds: TimeInterval
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(timeoutSeconds: TimeInterval) {
        self.timeoutSeconds = timeoutSeconds
    }

    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.timeoutTask = Task { [weak self] in
                let nanoseconds = UInt64((self?.timeoutSeconds ?? 20) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                await MainActor.run {
                    self?.finish(.failure(WebViewRenderedCrawlerError.timeout))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
