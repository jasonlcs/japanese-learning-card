import XCTest
@testable import JapaneseLearningCardCore

final class LLMClientEssayTests: XCTestCase {
    func testEssayRequestBodyRequiresJapaneseTitleAndTraditionalChinese() {
        let body = OpenAICompatibleLLMClient.essayRequestBody(
            theme: "旅行",
            vocabularyWords: ["旅"],
            settings: AppSettings()
        )
        let prompt = body.messages.map(\.content).joined(separator: "\n")

        XCTAssertTrue(prompt.contains(#""title" 必須是日文標題"#))
        XCTAssertTrue(prompt.contains("禁止中文標題"))
        XCTAssertTrue(prompt.contains("所有中文內容必須使用繁體中文"))
        XCTAssertTrue(prompt.contains("禁止簡體中文"))
    }

    func testDecodeEssayRejectsChineseTitle() {
        let content = """
        {
          "isValidPrompt": true,
          "validationError": "",
          "title": "我的一天",
          "paragraphs": [
            {
              "japanese": "今日は楽しい一日です。",
              "translation": "今天是愉快的一天。"
            }
          ]
        }
        """

        XCTAssertThrowsError(try OpenAICompatibleLLMClient.decodeEssay(from: content)) { error in
            XCTAssertTrue(error.localizedDescription.contains("title 必須是日文標題"))
        }
    }

    func testDecodeEssayConvertsChineseFieldsToTraditionalChinese() throws {
        let content = """
        {
          "isValidPrompt": true,
          "validationError": "",
          "title": "楽しい一日",
          "paragraphs": [
            {
              "japanese": "今日は楽しい一日です。",
              "translation": "今天学习日文很开心。"
            }
          ]
        }
        """

        let payload = try OpenAICompatibleLLMClient.decodeEssay(from: content)

        XCTAssertEqual(payload.title, "楽しい一日")
        XCTAssertEqual(payload.paragraphs.first?.japanese, "今日は楽しい一日です。")
        XCTAssertEqual(payload.paragraphs.first?.translation, "今天學習日文很開心。")
    }
}
