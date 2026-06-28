#if os(macOS)
import AppKit
import CoreGraphics

/// 偵測「正在簡報 / 投影」的狀態，讓 App 自動暫停卡片自動彈出。
///
/// 只用沙盒安全、不需任何授權的訊號：
/// - 螢幕鏡像（投影機常見作法）：`CGDisplayIsInMirrorSet`
/// - 有其他 App 的視窗鋪滿整個螢幕（原生全螢幕 / Keynote、PowerPoint 播放、
///   全螢幕視訊會議）：用 `CGWindowListCopyWindowInfo` 的視窗幾何判斷
///   （只讀座標大小，不需螢幕錄製權限）。
///
/// 偵測為「best effort」：抓不到也不會誤擋使用者，只是少了自動暫停。
@MainActor
final class PresentationDetector {
    /// 目前是否偵測到簡報情境。
    private(set) var isPresenting = false

    /// 狀態改變時回呼（值為最新的 isPresenting）。
    var onChange: ((Bool) -> Void)?

    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    func start() {
        evaluate()
        // 全螢幕視窗沒有通知可監聽，只能輪詢；8 秒一次對「簡報」這種秒數級
        // 的情境足夠即時，又不會耗電。
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        // 接投影機 / 開關鏡像會改變螢幕組態，立即重判一次。
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    private func evaluate() {
        let presenting = isScreenMirrored() || hasForeignFullscreenWindow()
        guard presenting != isPresenting else { return }
        isPresenting = presenting
        onChange?(presenting)
    }

    /// 是否有任何使用中的螢幕處於鏡像狀態（接投影機常見）。
    private func isScreenMirrored() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    /// 是否有「其他 App」的一般視窗鋪滿了某個螢幕（含蓋住選單列）。
    /// 一般最大化視窗會留下選單列，高度會比螢幕全高矮，因此不會誤判。
    private func hasForeignFullscreenWindow() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        let screenSizes = NSScreen.screens.map { $0.frame.size }
        guard !screenSizes.isEmpty else { return false }

        for window in windows {
            // 只看一般視窗層（layer 0），略過選單列、Dock、桌布等系統元件。
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            if let pid = window[kCGWindowOwnerPID as String] as? Int32, pid == ownPID { continue }
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            for size in screenSizes where bounds.width >= size.width - 1 && bounds.height >= size.height - 1 {
                return true
            }
        }
        return false
    }
}
#endif // os(macOS)
