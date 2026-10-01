import XCTest
@testable import JapaneseLearningCardCore

final class CardModelTests: XCTestCase {
    func testFormattedCreatedAtProducesStandardDateString() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.hour = 12
        let fixedDate = calendar.date(from: components)!

        let card = LearningCard(
            word: "日本語",
            reading: "にほんご",
            partOfSpeech: "名詞",
            meaningZh: "日語",
            grammarNoteZh: "",
            exampleJa: "日本語を勉強する",
            exampleZh: "學日文",
            sourceUrl: URL(string: "https://example.com")!,
            createdAt: fixedDate
        )

        XCTAssertEqual(card.formattedCreatedAt, "2026-10-01")
    }

    func testDecodeCardWithMissingCreatedAtDefaultsToNow() throws {
        let json = """
        {
          "word": "本",
          "reading": "ほん",
          "partOfSpeech": "名詞",
          "meaningZh": "書",
          "grammarNoteZh": "",
          "exampleJa": "本を読む",
          "exampleZh": "看書",
          "sourceUrl": "https://example.com"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let before = Date().addingTimeInterval(-1)
        let card = try decoder.decode(LearningCard.self, from: Data(json.utf8))
        let after = Date().addingTimeInterval(1)

        XCTAssertGreaterThanOrEqual(card.createdAt, before)
        XCTAssertLessThanOrEqual(card.createdAt, after)
        XCTAssertFalse(card.formattedCreatedAt.isEmpty)
    }

    func testDecodeCardWithEpochCreatedAtFallsBackToNow() throws {
        let json = """
        {
          "word": "本",
          "reading": "ほん",
          "partOfSpeech": "名詞",
          "meaningZh": "書",
          "grammarNoteZh": "",
          "exampleJa": "本を読む",
          "exampleZh": "看書",
          "sourceUrl": "https://example.com",
          "createdAt": "1970-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let before = Date().addingTimeInterval(-1)
        let card = try decoder.decode(LearningCard.self, from: Data(json.utf8))
        let after = Date().addingTimeInterval(1)

        XCTAssertGreaterThanOrEqual(card.createdAt, before)
        XCTAssertLessThanOrEqual(card.createdAt, after)
    }
}
