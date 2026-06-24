import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol Crawling: Sendable {
    func crawl(source: Source) async throws -> CrawledDocument
}

public enum WebCrawlerError: LocalizedError {
    case payloadTooLarge
    case unsafeHost

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: "Crawled page exceeded the 5 MB safety limit."
        case .unsafeHost: "Crawled URL resolves to a blocked address."
        }
    }
}

public struct WebCrawler: Crawling {
    public static let maxPayloadBytes = 5 * 1024 * 1024
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private let extractor: HTMLTextExtractor
    private let session: URLSession

    public init(extractor: HTMLTextExtractor = HTMLTextExtractor(), session: URLSession = WebCrawler.makeDefaultSession()) {
        self.extractor = extractor
        self.session = session
    }

    public static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
            "Accept-Language": "ja,en-US;q=0.9,en;q=0.8",
            "Sec-Fetch-Dest": "document",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-Site": "none",
            "Upgrade-Insecure-Requests": "1"
        ]
        return URLSession(configuration: config)
    }

    public func crawl(source: Source) async throws -> CrawledDocument {
        try SourceValidator().validate(source.url)
        let (data, response) = try await session.data(from: source.url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        if data.count > Self.maxPayloadBytes {
            throw WebCrawlerError.payloadTooLarge
        }

        let html = String(decoding: data, as: UTF8.self)
        let extracted = extractor.extract(html: html)
        return CrawledDocument(
            sourceId: source.id,
            url: source.url,
            title: extracted.title,
            plainText: extracted.text,
            contentHash: ContentHash.sha256(extracted.text)
        )
    }
}
