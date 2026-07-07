import XCTest
import JapaneseLearningCardCore
@testable import JapaneseLearningCardUI

private struct InMemorySecretStore: SecretStore {
    func saveAPIKey(_ apiKey: String, reference: String) throws {}
    func apiKey(reference: String) throws -> String? { nil }
    func deleteAPIKey(reference: String) throws {}
}

@MainActor
final class CardTimerStateTests: XCTestCase {
    private func makeViewModel() async throws -> AppViewModel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("card-timer-tests-\(UUID().uuidString).sqlite")
        let store = await AppStore(fileURL: url)
        try await store.update { state in
            state.cards = [
                LearningCard(
                    word: "勉強",
                    reading: "べんきょう",
                    partOfSpeech: "名詞",
                    meaningZh: "學習",
                    grammarNoteZh: "",
                    exampleJa: "勉強する。",
                    exampleZh: "學習。",
                    sourceUrl: URL(string: "https://example.com")!
                )
            ]
        }
        let viewModel = AppViewModel(store: store, secretStore: InMemorySecretStore())
        await viewModel.reload()
        return viewModel
    }

    /// 快速複習結束後（按停止或時間到），popover 還開著時必須恢復
    /// 一般的自動關閉倒數，否則進度條會停用（變暗且永遠不動）。
    func testStoppingQuickReviewRestoresVisibleCardCountdown() async throws {
        let viewModel = try await makeViewModel()
        viewModel.popoverDidShow(isMouseInside: false)
        XCTAssertTrue(viewModel.visibleCardTimerState.isActive)

        viewModel.startQuickReview()
        XCTAssertTrue(viewModel.isQuickReviewActive)
        XCTAssertTrue(viewModel.visibleCardTimerState.isActive)

        viewModel.stopQuickReview()
        XCTAssertFalse(viewModel.isQuickReviewActive)
        XCTAssertTrue(
            viewModel.visibleCardTimerState.isActive,
            "停止快速複習後倒數應恢復，而不是停用讓進度條變暗不動"
        )
        XCTAssertGreaterThan(viewModel.visibleCardTimerState.remainingFraction(), 0)
    }

    /// 互動暫停時剩餘秒數要有下限，避免在倒數快歸零時滑鼠移入，
    /// 進度條凍結在寬度 ≈ 0（看起來像消失）。
    func testPauseKeepsMinimumRemainingSoBarStaysVisible() async throws {
        let viewModel = try await makeViewModel()
        viewModel.popoverDidShow(isMouseInside: false)

        viewModel.pauseAutoCloseForInteraction()
        let fraction = viewModel.visibleCardTimerState.remainingFraction(
            at: Date().addingTimeInterval(3600)
        )
        let duration = viewModel.visibleCardTimerState.duration
        XCTAssertGreaterThanOrEqual(
            fraction * duration, 3,
            "暫停後保留的剩餘秒數不得低於下限，進度條才不會凍結在看不見的寬度"
        )
    }
}
