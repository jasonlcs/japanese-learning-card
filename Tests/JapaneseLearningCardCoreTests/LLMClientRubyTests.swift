import XCTest
@testable import JapaneseLearningCardCore

final class LLMClientRubyTests: XCTestCase {
    func testDecodeCardsKeepsValidRubyMetadata() throws {
        let content = """
        {
          "cards": [
            {
              "word": "勉強",
              "reading": "べんきょう",
              "wordRuby": [{"base": "勉強", "ruby": "べんきょう"}],
              "partOfSpeech": "名詞",
              "meaningZh": "學習",
              "grammarNoteZh": "重點：常用語\\nよく使う形：勉強する\\n関連語：学習",
              "jlptLevel": "N4",
              "verbFormType": "非動詞",
              "exampleJa": "毎日、日本語を勉強します。",
              "exampleReading": "まいにち、にほんごをべんきょうします。",
              "exampleRuby": [
                {"base": "毎日", "ruby": "まいにち"},
                {"base": "、", "ruby": ""},
                {"base": "日本語", "ruby": "にほんご"},
                {"base": "を", "ruby": ""},
                {"base": "勉強", "ruby": "べんきょう"},
                {"base": "します。", "ruby": ""}
              ],
              "exampleZh": "我每天學日文。"
            }
          ]
        }
        """

        let cards = try OpenAICompatibleLLMClient.decodeCards(
            from: content,
            sourceURL: URL(string: "https://example.com")!,
            includeN5: true
        )

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].wordRuby, [RubySegment(base: "勉強", ruby: "べんきょう")])
        XCTAssertTrue(RubySupport.isUsable(cards[0].exampleRuby, for: cards[0].exampleJa))
    }

    func testDecodeCardsDiscardsInvalidRubyMetadataWithoutDroppingCard() throws {
        let content = """
        {
          "cards": [
            {
              "word": "勉強",
              "reading": "べんきょう",
              "wordRuby": [{"base": "英語", "ruby": "えいご"}],
              "partOfSpeech": "名詞",
              "meaningZh": "學習",
              "grammarNoteZh": "重點：常用語\\nよく使う形：勉強する\\n関連語：学習",
              "jlptLevel": "N4",
              "verbFormType": "非動詞",
              "exampleJa": "毎日、日本語を勉強します。",
              "exampleReading": "まいにち、にほんごをべんきょうします。",
              "exampleRuby": [{"base": "毎日、英語", "ruby": "まいにち、えいご"}],
              "exampleZh": "我每天學日文。"
            }
          ]
        }
        """

        let cards = try OpenAICompatibleLLMClient.decodeCards(
            from: content,
            sourceURL: URL(string: "https://example.com")!,
            includeN5: true
        )

        XCTAssertEqual(cards.count, 1)
        XCTAssertTrue(cards[0].wordRuby.isEmpty)
        XCTAssertTrue(cards[0].exampleRuby.isEmpty)
    }

    func testDecodeRubyBackfillValidatesAgainstSourceCards() throws {
        let cardId = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let source = LearningCard(
            id: cardId,
            word: "勉強",
            reading: "べんきょう",
            partOfSpeech: "名詞",
            meaningZh: "學習",
            grammarNoteZh: "重點：常用語\nよく使う形：勉強する\n関連語：学習",
            jlptLevel: .n4,
            verbFormType: .notVerb,
            exampleJa: "毎日、日本語を勉強します。",
            exampleReading: "まいにち、にほんごをべんきょうします。",
            exampleZh: "我每天學日文。",
            sourceUrl: URL(string: "https://example.com")!
        )
        let content = """
        {
          "cards": [
            {
              "id": "\(cardId.uuidString)",
              "wordRuby": [{"base": "勉強", "ruby": "べんきょう"}],
              "exampleRuby": [{"base": "毎日、日本語を勉強します。", "ruby": "まいにち、にほんごをべんきょうします。"}]
            }
          ]
        }
        """

        let results = try OpenAICompatibleLLMClient.decodeRubyBackfill(from: content, sourceCards: [source])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].cardId, cardId)
        XCTAssertEqual(results[0].wordRuby, [RubySegment(base: "勉強", ruby: "べんきょう")])
    }
}
