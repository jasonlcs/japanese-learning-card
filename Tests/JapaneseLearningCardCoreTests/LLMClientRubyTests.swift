import XCTest
@testable import JapaneseLearningCardCore

final class LLMClientRubyTests: XCTestCase {
    func testRubyAnnotationUnitsSplitJapaneseParagraphsBySentence() {
        let units = OpenAICompatibleLLMClient.rubyAnnotationUnits(for: [
            "短文タイトル",
            "今日は雨です。傘を持ちます！大丈夫？",
        ])

        XCTAssertEqual(units.map(\.sourceTextIndex), [0, 1, 1, 1])
        XCTAssertEqual(units.map(\.text), [
            "短文タイトル",
            "今日は雨です。",
            "傘を持ちます！",
            "大丈夫？",
        ])
    }

    func testRubyAnnotationUnitsPreserveClosingQuotesAndWhitespace() {
        let units = OpenAICompatibleLLMClient.rubyAnnotationUnits(for: [
            "彼は「行きます。」と言った。 次の文です。",
        ])

        XCTAssertEqual(units.map(\.text), [
            "彼は「行きます。」と言った。 ",
            "次の文です。",
        ])
        XCTAssertEqual(units.map(\.text).joined(), "彼は「行きます。」と言った。 次の文です。")
    }

    func testMergeRubyAnnotationUnitResultsKeepsPlainTextForFailedSentence() {
        let texts = ["今日は雨です。傘を持ちます。大丈夫です。"]
        let units = OpenAICompatibleLLMClient.rubyAnnotationUnits(for: texts)
        let merged = OpenAICompatibleLLMClient.mergeRubyAnnotationUnitResults(
            texts: texts,
            units: units,
            unitResults: [
                [RubySegment(base: "今日", ruby: "きょう"), RubySegment(base: "は", ruby: ""), RubySegment(base: "雨", ruby: "あめ"), RubySegment(base: "です。", ruby: "")],
                [],
                [RubySegment(base: "大丈夫", ruby: "だいじょうぶ"), RubySegment(base: "です。", ruby: "")],
            ]
        )

        XCTAssertTrue(RubySupport.isUsable(merged[0], for: texts[0]))
        XCTAssertEqual(merged[0].map(\.base).joined(), texts[0])
        XCTAssertTrue(merged[0].contains(RubySegment(base: "今日", ruby: "きょう")))
        XCTAssertTrue(merged[0].contains(RubySegment(base: "傘を持ちます。", ruby: "")))
        XCTAssertTrue(merged[0].contains(RubySegment(base: "大丈夫", ruby: "だいじょうぶ")))
    }

    func testDecodeRubyForTextsRepairsMismatchedModelBaseToOriginalText() async throws {
        let content = """
        {
          "results": [
            {
              "index": 0,
              "ruby": [
                {"base": "毎日", "ruby": "まいにち"},
                {"base": "英語", "ruby": "えいご"},
                {"base": "を", "ruby": ""},
                {"base": "勉強", "ruby": "べんきょう"},
                {"base": "します。", "ruby": ""}
              ]
            }
          ]
        }
        """
        let source = "毎日、日本語を勉強します。"

        let results = try await OpenAICompatibleLLMClient.decodeRubyForTexts(from: content, sourceTexts: [source])

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(RubySupport.isUsable(results[0], for: source))
        XCTAssertFalse(results[0].isEmpty)
        XCTAssertTrue(results[0].contains(RubySegment(base: "毎日", ruby: "まいにち")))
        XCTAssertTrue(results[0].contains(RubySegment(base: "勉強", ruby: "べんきょう")))
    }

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
