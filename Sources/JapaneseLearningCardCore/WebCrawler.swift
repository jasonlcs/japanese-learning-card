import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol Crawling: Sendable {
    func crawl(source: Source) async throws -> CrawledDocument
}

public struct WebCrawler: Crawling {
    private let extractor: HTMLTextExtractor
    private let session: URLSession

    public init(extractor: HTMLTextExtractor = HTMLTextExtractor(), session: URLSession = .shared) {
        self.extractor = extractor
        self.session = session
    }

    public func crawl(source: Source) async throws -> CrawledDocument {
        let (data, response) = try await session.data(from: source.url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
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
