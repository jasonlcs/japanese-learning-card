import XCTest
@testable import JapaneseLearningCardCore

final class DocxBuilderTests: XCTestCase {

    // MARK: – escapeXML

    func testEscapeXMLHandlesSpecialCharacters() {
        XCTAssertEqual(DocxBuilder.escapeXML("a & b"), "a &amp; b")
        XCTAssertEqual(DocxBuilder.escapeXML("<tag>"), "&lt;tag&gt;")
        XCTAssertEqual(DocxBuilder.escapeXML("say \"hi\""), "say &quot;hi&quot;")
        XCTAssertEqual(DocxBuilder.escapeXML("it's"), "it&apos;s")
        XCTAssertEqual(DocxBuilder.escapeXML("plain"), "plain")
    }

    // MARK: – buildRunXML: plain run (no ruby)

    func testBuildRunXMLPlainRunContainsXmlSpacePreserve() {
        let seg = RubySegment(base: "plain text", ruby: "")
        let xml = DocxBuilder.buildRunXML(segment: seg, baseSize: 24, rubySize: 12)
        XCTAssertTrue(xml.contains("xml:space=\"preserve\""),
                      "Plain <w:t> must carry xml:space=\"preserve\"")
        XCTAssertFalse(xml.contains("<w:ruby>"),
                       "Plain run must not contain <w:ruby>")
        XCTAssertTrue(xml.contains("plain text"))
    }

    func testBuildRunXMLPlainRunEscapesSpecialChars() {
        let seg = RubySegment(base: "A & B < C", ruby: "")
        let xml = DocxBuilder.buildRunXML(segment: seg, baseSize: 24, rubySize: 12)
        XCTAssertTrue(xml.contains("A &amp; B &lt; C"))
    }

    func testBuildRunXMLPlainRunWithBold() {
        let seg = RubySegment(base: "bold", ruby: "")
        let xml = DocxBuilder.buildRunXML(segment: seg, baseSize: 36, rubySize: 18, bold: true)
        XCTAssertTrue(xml.contains("<w:b/>"))
    }

    // MARK: – buildRunXML: ruby run

    func testBuildRunXMLRubyIsDirectChildOfParagraph() {
        // w:ruby must NOT be wrapped inside w:r
        let seg = RubySegment(base: "漢字", ruby: "かんじ")
        let xml = DocxBuilder.buildRunXML(segment: seg, baseSize: 24, rubySize: 12)

        // The output must start with whitespace + <w:ruby>, never <w:r>
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.hasPrefix("<w:ruby>"),
                      "ruby run must begin with <w:ruby>, got: \(trimmed.prefix(40))")
    }

    func testBuildRunXMLRubyContainsRequiredElements() {
        let seg = RubySegment(base: "日本語", ruby: "にほんご")
        let xml = DocxBuilder.buildRunXML(segment: seg, baseSize: 24, rubySize: 12)

        XCTAssertTrue(xml.contains("<w:rubyPr>"))
        XCTAssertTrue(xml.contains("<w:rt>"))
        XCTAssertTrue(xml.contains("<w:rubyBase>"))
        XCTAssertTrue(xml.contains("<w:lid w:val=\"ja-JP\"/>"))
        XCTAssertTrue(xml.contains("xml:space=\"preserve\""))
    }

    func testBuildRunXMLRubyBaseSizePropagated() {
        let seg = RubySegment(base: "字", ruby: "じ")
        let xml = DocxBuilder.buildRunXML(segment: seg, baseSize: 36, rubySize: 18, bold: true)

        XCTAssertTrue(xml.contains("w:val=\"36\""),  "baseSize must appear in sz elements")
        XCTAssertTrue(xml.contains("w:val=\"18\""),  "rubySize must appear in sz elements")
        XCTAssertTrue(xml.contains("<w:b/>"),         "bold flag must propagate to rubyBase run")
    }

    func testBuildRunXMLRubyTextEscaped() {
        let seg = RubySegment(base: "<漢>", ruby: "あ&い")
        let xml = DocxBuilder.buildRunXML(segment: seg, baseSize: 24, rubySize: 12)

        XCTAssertTrue(xml.contains("&lt;漢&gt;"))
        XCTAssertTrue(xml.contains("あ&amp;い"))
    }

    // MARK: – buildDocumentXML

    func testBuildDocumentXMLContainsTitle() {
        let xml = DocxBuilder.buildDocumentXML(
            title: "テスト",
            titleRuby: nil,
            theme: "学習",
            paragraphs: []
        )
        XCTAssertTrue(xml.contains("テスト"))
        XCTAssertTrue(xml.contains("学習"))
    }

    func testBuildDocumentXMLUsesRubyForTitle() {
        let titleRuby = [RubySegment(base: "勉強", ruby: "べんきょう")]
        let xml = DocxBuilder.buildDocumentXML(
            title: "勉強",
            titleRuby: titleRuby,
            theme: "テスト",
            paragraphs: []
        )
        XCTAssertTrue(xml.contains("べんきょう"))
        // The ruby element must not be wrapped in <w:r>
        let rubyIdx = xml.range(of: "<w:ruby>")!
        let before = xml[xml.startIndex..<rubyIdx.lowerBound]
        XCTAssertFalse(before.hasSuffix("<w:r>"),
                       "<w:ruby> must not be immediately preceded by <w:r>")
    }

    func testBuildDocumentXMLFallsBackToPlainTitleWhenRubyInvalid() {
        // Provide ruby whose base doesn't match the title → should fall back
        let badRuby = [RubySegment(base: "全然違う", ruby: "ぜんぜんちがう")]
        let xml = DocxBuilder.buildDocumentXML(
            title: "勉強",
            titleRuby: badRuby,
            theme: "テスト",
            paragraphs: []
        )
        XCTAssertTrue(xml.contains("勉強"))
        XCTAssertFalse(xml.contains("全然違う"))
    }

    func testBuildDocumentXMLRendersBodyParagraphs() {
        let para = ArticleParagraph(
            japanese: "毎日勉強します。",
            ruby: [
                RubySegment(base: "毎日", ruby: "まいにち"),
                RubySegment(base: "勉強", ruby: "べんきょう"),
                RubySegment(base: "します。", ruby: ""),
            ],
            translation: "我每天學習。"
        )
        let xml = DocxBuilder.buildDocumentXML(
            title: "題名",
            titleRuby: nil,
            theme: "学習",
            paragraphs: [para]
        )
        XCTAssertTrue(xml.contains("まいにち"))
        XCTAssertTrue(xml.contains("べんきょう"))
        XCTAssertTrue(xml.contains("我每天學習。"))
    }

    func testBuildDocumentXMLSkipsEmptyTranslations() {
        let para = ArticleParagraph(
            japanese: "日本語",
            ruby: [],
            translation: "   "   // whitespace only → should be omitted
        )
        let xml = DocxBuilder.buildDocumentXML(
            title: "T",
            titleRuby: nil,
            theme: "テーマ",
            paragraphs: [para]
        )
        // The translation paragraph run text should not appear (only whitespace)
        XCTAssertFalse(xml.contains("<w:t xml:space=\"preserve\">   </w:t>"))
    }

    func testBuildDocumentXMLIsWellFormedXML() throws {
        let ruby = [
            RubySegment(base: "漢字", ruby: "かんじ"),
            RubySegment(base: "です。", ruby: ""),
        ]
        let para = ArticleParagraph(japanese: "漢字です。", ruby: ruby, translation: "Kanji.")
        let xml = DocxBuilder.buildDocumentXML(
            title: "テスト",
            titleRuby: [RubySegment(base: "テスト", ruby: "")],
            theme: "テーマ",
            paragraphs: [para]
        )
        // Parse as XML to verify well-formedness
        let data = Data(xml.utf8)
        let _ = try XMLDocument(data: data, options: [])
    }

    // MARK: – buildDocx (ZIP output)

    func testBuildDocxProducesValidZipSignature() {
        let data = DocxBuilder.buildDocx(
            title: "テスト",
            titleRuby: nil,
            theme: "テーマ",
            paragraphs: []
        )
        // ZIP local-file header signature: PK\x03\x04
        XCTAssertGreaterThan(data.count, 4)
        XCTAssertEqual(data[0], 0x50)  // P
        XCTAssertEqual(data[1], 0x4b)  // K
        XCTAssertEqual(data[2], 0x03)
        XCTAssertEqual(data[3], 0x04)
    }

    func testBuildDocxContainsWordDocumentXMLEntry() {
        let data = DocxBuilder.buildDocx(
            title: "テスト",
            titleRuby: nil,
            theme: "テーマ",
            paragraphs: []
        )
        // The entry name "word/document.xml" must appear in the ZIP bytes
        let str = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(str.contains("word/document.xml"))
        XCTAssertTrue(str.contains("word/_rels/document.xml.rels"),
                      "ZIP must include word/_rels/document.xml.rels for OOXML conformance")
        XCTAssertTrue(str.contains("[Content_Types].xml"))
    }
}
