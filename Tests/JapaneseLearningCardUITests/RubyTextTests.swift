import XCTest
import JapaneseLearningCardCore
@testable import JapaneseLearningCardUI

final class RubyTextTests: XCTestCase {
    func testRubyTextCanBeConstructedWithValidSegments() {
        let view = RubyText(
            segments: [RubySegment(base: "勉強", ruby: "べんきょう")],
            fallback: "勉強",
            baseFont: .headline,
            rubyFont: .caption
        )

        XCTAssertFalse(Mirror(reflecting: view).children.isEmpty)
    }
}
