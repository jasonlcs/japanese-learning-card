import XCTest
@testable import JapaneseLearningCardUI

#if os(macOS)
final class IdleDetectorTests: XCTestCase {
    func testIsIdlePureLogic() {
        XCTAssertFalse(IdleDetector.isIdle(idleSeconds: 0, threshold: 900))
        XCTAssertFalse(IdleDetector.isIdle(idleSeconds: 899, threshold: 900))
        XCTAssertTrue(IdleDetector.isIdle(idleSeconds: 900, threshold: 900))
        XCTAssertTrue(IdleDetector.isIdle(idleSeconds: 901, threshold: 900))
        // threshold <= 0 表示永不觸發。
        XCTAssertFalse(IdleDetector.isIdle(idleSeconds: 99999, threshold: 0))
    }

    func testIsIdleResolvedPureLogic() {
        XCTAssertTrue(IdleDetector.isIdleResolved(idleSeconds: 0, threshold: 900))
        XCTAssertTrue(IdleDetector.isIdleResolved(idleSeconds: 674, threshold: 900))
        XCTAssertFalse(IdleDetector.isIdleResolved(idleSeconds: 675, threshold: 900))
        XCTAssertTrue(IdleDetector.isIdleResolved(idleSeconds: 99999, threshold: 0))
    }
}

@MainActor
final class IdleDetectorBehaviorTests: XCTestCase {
    func testTriggerAndReleaseWithHysteresis() {
        let detector = IdleDetector()
        var states: [Bool] = []
        detector.idleSecondsProvider = { 300 }
        detector.onChange = { states.append($0) }
        detector.threshold = 900

        // 還沒到門檻：不觸發。
        detector.evaluate()
        XCTAssertFalse(detector.isIdle)

        // 超過門檻：觸發閒置。
        detector.idleSecondsProvider = { 901 }
        detector.evaluate()
        XCTAssertTrue(detector.isIdle)

        // 只是稍微低於門檻（遲滯區內）：仍保持閒置，不抖動。
        detector.idleSecondsProvider = { 800 }
        detector.evaluate()
        XCTAssertTrue(detector.isIdle)

        // 明顯低於門檻（< 75%）：解除閒置。
        detector.idleSecondsProvider = { 60 }
        detector.evaluate()
        XCTAssertFalse(detector.isIdle)

        XCTAssertEqual(states, [true, false], "只在狀態真的改變時才回呼")
    }
}
#endif
