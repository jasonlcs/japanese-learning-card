import XCTest
@testable import JapaneseLearningCardCore

final class RubySupportTests: XCTestCase {
    func testOldLearningCardJSONDecodesWithEmptyRubyArrays() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "word": "勉強",
          "reading": "べんきょう",
          "partOfSpeech": "名詞",
          "meaningZh": "學習",
          "grammarNoteZh": "重點：常用語\\nよく使う形：勉強する\\n関連語：学習",
          "jlptLevel": "N5",
          "verbFormType": "非動詞",
          "exampleJa": "毎日、日本語を勉強します。",
          "exampleReading": "まいにち、にほんごをべんきょうします。",
          "exampleZh": "我每天學日文。",
          "sourceUrl": "https://example.com",
          "status": "new",
          "createdAt": "2026-01-01T00:00:00Z",
          "shownCount": 0,
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let card = try decoder.decode(LearningCard.self, from: Data(json.utf8))

        XCTAssertEqual(card.word, "勉強")
        XCTAssertTrue(card.wordRuby.isEmpty)
        XCTAssertTrue(card.exampleRuby.isEmpty)
    }

    func testRubySegmentsAreUsableWhenBaseReconstructsText() {
        let segments = [
            RubySegment(base: "毎日", ruby: "まいにち"),
            RubySegment(base: "、", ruby: ""),
            RubySegment(base: "日本語", ruby: "にほんご"),
            RubySegment(base: "を", ruby: ""),
            RubySegment(base: "勉強", ruby: "べんきょう"),
            RubySegment(base: "します。", ruby: "")
        ]

        XCTAssertTrue(RubySupport.isUsable(segments, for: "毎日、日本語を勉強します。"))
    }

    func testRubySegmentsAreRejectedWhenBaseDoesNotReconstructText() {
        let segments = [
            RubySegment(base: "毎日", ruby: "まいにち"),
            RubySegment(base: "英語", ruby: "えいご")
        ]

        XCTAssertFalse(RubySupport.isUsable(segments, for: "毎日、日本語を勉強します。"))
        XCTAssertTrue(RubySupport.validated(segments, for: "毎日、日本語を勉強します。").isEmpty)
    }

    func testAppSettingsDecodeDefaultsCompletedMigrationsToEmptyArray() throws {
        let json = #"{"providerConfig":{"preset":"openAI","baseURL":"https://api.openai.com/v1","model":"gpt-4.1-mini","apiKeyKeychainRef":"default","extraHeaders":{},"structuredOutput":"jsonObject"}}"#

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertTrue(settings.completedMigrations.isEmpty)
    }

    func testLearningCardNeedsRubyBackfillWhenRubyIsMissing() {
        let card = makeCard(wordRuby: [], exampleRuby: [])

        XCTAssertTrue(card.needsRubyBackfill)
    }

    func testLearningCardDoesNotNeedRubyBackfillWhenRubyIsUsable() {
        let card = makeCard(
            wordRuby: [RubySegment(base: "勉強", ruby: "べんきょう")],
            exampleRuby: [
                RubySegment(base: "毎日", ruby: "まいにち"),
                RubySegment(base: "、", ruby: ""),
                RubySegment(base: "日本語", ruby: "にほんご"),
                RubySegment(base: "を", ruby: ""),
                RubySegment(base: "勉強", ruby: "べんきょう"),
                RubySegment(base: "します。", ruby: "")
            ]
        )

        XCTAssertFalse(card.needsRubyBackfill)
    }

    private func makeCard(wordRuby: [RubySegment], exampleRuby: [RubySegment]) -> LearningCard {
        LearningCard(
            word: "勉強",
            reading: "べんきょう",
            partOfSpeech: "名詞",
            meaningZh: "學習",
            grammarNoteZh: "重點：常用語\nよく使う形：勉強する\n関連語：学習",
            jlptLevel: .n4,
            verbFormType: .notVerb,
            exampleJa: "毎日、日本語を勉強します。",
            exampleReading: "まいにち、にほんごをべんきょうします。",
            wordRuby: wordRuby,
            exampleRuby: exampleRuby,
            exampleZh: "我每天學日文。",
            sourceUrl: URL(string: "https://example.com")!
        )
    }
}
