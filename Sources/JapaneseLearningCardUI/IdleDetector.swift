#if os(macOS)
import AppKit
import CoreGraphics

/// 偵測「使用者已閒置（鍵盤／滑鼠都沒動）」的狀態，讓 App 自動暫停卡片
/// 自動彈出（不動其它排程）。
///
/// 只用沙盒安全、不需任何授權的訊號：
/// `CGEventSource.secondsSinceLastEventType(.combinedSessionState, ...)` 回傳
/// 上次任何輸入事件到現在的秒數；不需要輔助使用（Accessibility）權限。
///
/// 採用輪詢（每 10 秒）而非事件監聽，因為全域事件監聽（`NSEvent.addGlobal
/// Monitor`）需要輔助使用權限，輪詢對「分鐘級」的閒置情境已足夠即時又不耗電。
@MainActor
final class IdleDetector {
    /// 目前是否已判定為閒置。
    private(set) var isIdle = false

    /// 閒置幾秒後判定為閒置。小於等於 0 表示永不觸發。
    var threshold: TimeInterval = 0 {
        didSet { evaluate() }
    }

    /// 狀態改變時回呼（值為最新的 isIdle）。
    var onChange: ((Bool) -> Void)?

    /// 供測試替換；預設讀取系統輸入事件間隔。
    var idleSecondsProvider: () -> TimeInterval = {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    private var pollTimer: Timer?

    /// 是否已判斷為閒置的純邏輯，供單元測試。
    /// 用遲滯避免在門檻邊界抖動：閒置秒數要低於門檻的 3/4 才解除。
    nonisolated static func isIdle(idleSeconds: TimeInterval, threshold: TimeInterval) -> Bool {
        guard threshold > 0 else { return false }
        return idleSeconds >= threshold
    }

    nonisolated static func isIdleResolved(idleSeconds: TimeInterval, threshold: TimeInterval) -> Bool {
        guard threshold > 0 else { return true }
        return idleSeconds < threshold * 0.75
    }

    func start() {
        guard pollTimer == nil else { return }
        evaluate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func evaluate() {
        let idleSeconds = idleSecondsProvider()
        let shouldBeIdle: Bool
        if isIdle {
            // 已閒置：只在明顯低於門檻（使用者真的回來動了）才解除。
            shouldBeIdle = !Self.isIdleResolved(idleSeconds: idleSeconds, threshold: threshold)
        } else {
            shouldBeIdle = Self.isIdle(idleSeconds: idleSeconds, threshold: threshold)
        }
        guard shouldBeIdle != isIdle else { return }
        isIdle = shouldBeIdle
        onChange?(isIdle)
    }
}
#endif // os(macOS)
