# iOS App 開發可行性報告

## 專案概況

Japanese Learning Card 目前是一款 macOS 選單列 App，核心功能包含：

- 爬取使用者設定的 URL 並抽取日語學習卡片
- AI 生成日語文章與單字卡（支援 JLPT N1–N5）
- 多選項 AI 測驗題
- CloudKit 跨裝置同步
- SQLite 本地儲存、Keychain 存放 API 金鑰

---

## 現有架構對 iOS 的適用性

程式碼分為三個 Swift Package targets：

| Target | 說明 | 程式碼規模 |
|--------|------|-----------|
| `JapaneseLearningCardCore` | 核心業務邏輯（AI、SQLite、CloudKit、爬蟲、卡片演算法） | ~4,200 行 |
| `JapaneseLearningCard` | macOS UI 層（選單列、AppKit） | ~4,600 行 |
| `JapaneseLearningCardCoreChecks` | 驗證執行檔 | ~1,600 行 |

---

## 一、可直接移植（約 70% 程式碼）

`JapaneseLearningCardCore` 完全沒有 `AppKit` 或 `UIKit` 依賴，所有模組可直接在 iOS 上編譯使用：

| 模組 | iOS 可用性 | 說明 |
|------|-----------|------|
| `Models.swift` | ✅ 直接可用 | 純 Foundation 資料模型 |
| `LLMClient.swift` | ✅ 直接可用 | 使用 `URLSession`，跨平台 |
| `AppStore.swift` | ✅ 直接可用 | SQLite3 在 iOS 上可用 |
| `KeychainStore.swift` | ✅ 直接可用 | `Security` framework 跨平台 |
| `CloudKitBacking/Transport/Schema` | ✅ 直接可用 | CloudKit 原生支援 iOS |
| `Merger.swift` | ✅ 直接可用 | 純 Swift 3-way merge 演算法 |
| `LearningPipeline.swift` | ✅ 直接可用 | 卡片生成流程 |
| `WebCrawler.swift` | ✅ 直接可用 | 使用 `URLSession` |
| `HTMLTextExtractor.swift` | ✅ 直接可用 | 純文字解析 |
| `StorageMode.swift` | ✅ 直接可用 | 儲存模式選擇 |

**最昂貴的部分（AI 呼叫、CloudKit 同步、SQLite 儲存、3-way merge）一行不用改。**

---

## 二、需修改或重寫的部分（約 30% 程式碼）

### 2.1 入口點：`JapaneseLearningCardApp.swift` ❌ 需完全重寫

現況：使用 `NSApplication`、`NSStatusItem`、`NSPopover`、`NSMenu`（macOS 選單列架構）。

iOS 替代方案：改用 SwiftUI `@main struct App: App` + `WindowGroup`，配合 `TabView` 作主導覽。

### 2.2 `AppViewModel.swift` ⚠️ 需部分修改

匯入 `AppKit`，含 popover 顯示/隱藏的 callback（`requestShowPopover`、`requestClosePopover`）。

- **保留**：所有核心狀態管理（`@Published` 屬性、背景排程、卡片邏輯）
- **移除**：popover 相關 callback、選單列互動邏輯

### 2.3 `RootView.swift`（2,495 行）⚠️ 需適度修改

多數 SwiftUI view 邏輯可直接重用，主要替換 macOS 專屬型別：

| 原有 macOS 寫法 | iOS 替換 |
|----------------|---------|
| `Color(nsColor: .windowBackgroundColor)` | `Color(.systemBackground)` |
| `minWidth: 520`（固定寬度） | 響應式佈局 |
| `NSColor`、`NSImage` 參照 | 移除或改為 SwiftUI 原生型別 |

### 2.4 `PresentationDetector.swift` ❌ 直接移除

偵測「正在簡報/投影」狀態，使用 `CGWindowListCopyWindowInfo`、`NSScreen.screens`，iOS 完全無對應概念，直接刪除即可，不影響任何功能。

### 2.5 `Updater.swift` + Sparkle 依賴 ❌ 直接移除

Sparkle 是 macOS 專屬自動更新框架。iOS 透過 App Store 自動更新，不需要 Sparkle。

### 2.6 `BrowserFallbackCrawler.swift` ⚠️ 需輕微調整

使用 `WKWebView`（WebKit），iOS 也支援。但 iOS 上 `WKWebView` 對背景執行有額外限制，需確認前景爬取情境下的行為（詳見第四節）。

---

## 三、iOS 上不支援或行為有差異的功能

| 功能 | macOS | iOS | 說明 |
|------|-------|-----|------|
| 選單列常駐 | ✅ NSStatusItem | ❌ 無對應 | iOS 沒有全域選單列，需改為 App 主畫面 |
| 選單列定時彈出卡片 | ✅ NSPopover | ❌ 無對應 | 需改為通知（暫緩，見下節） |
| 系統全螢幕偵測 | ✅ PresentationDetector | ❌ 不可能 | 直接移除，iOS 沙盒無法查看其他 App 視窗 |
| App 自動更新 | ✅ Sparkle | ✅ App Store 自動 | 直接移除 Sparkle，交由 App Store 處理 |
| 背景爬蟲執行 | ✅ 常駐背景 | ⚠️ 受限 | iOS 限制背景執行，改為前景觸發（見第四節） |
| 長時間背景 AI 呼叫 | ✅ 常駐背景 | ⚠️ 受限 | 與爬蟲一同改為前景處理 |
| iCloud Drive 檔案同步 | ✅ 支援 | ⚠️ 路徑不同 | iOS iCloud Drive 路徑為 `NSFileProviderManager`，需調整 `StorageMode` |
| CloudKit 同步 | ✅ 完整支援 | ✅ 完整支援 | 直接可用，同一 container 跨裝置共享 |
| Keychain API 金鑰 | ✅ 完整支援 | ✅ 完整支援 | 直接可用 |

---

## 四、設計調整建議（依優先順序）

### 4.1 定時推播（暫緩）

macOS 版的「定時彈出卡片」對使用體驗影響最大，但 iOS 的實作需要額外設計，**建議 v1.0 先不實作**，待核心功能穩定後再加入：

- 本地通知（`UNUserNotificationCenter`）：推播標題可帶單字，點擊進入 App
- WidgetKit：主畫面或鎖定畫面 widget 顯示當前卡片（進階功能）

### 4.2 爬蟲改為前景觸發 ✅ 可行，且簡化實作

iOS 前景執行無時間限制，`URLSession` 與 `WKWebView` 均可正常使用。建議策略：

1. 使用者開啟 App → 自動觸發爬蟲（與 macOS 的 `applicationDidBecomeActive` 行為一致）
2. 提供「立即重新爬取」按鈕供手動觸發
3. AI 卡片生成也在前景完成，過程顯示進度指示

這樣的設計實際上比 macOS 版更簡單，省去背景排程的複雜度。

### 4.3 CloudKit 同步是直接加分項

現有 CloudKit 同步架構對 iOS 是免費贈送的優勢：
- 同一 CloudKit container 跨 macOS + iOS 共用
- 學習進度（卡片狀態、歷史）自動同步
- 3-way merge 邏輯已完整實作，無需修改

### 4.4 UI 導覽建議

macOS 選單列 popover 對應 iOS 的建議佈局：

```
TabView
├── 卡片（CardView）          ← 主頁，App 開啟即顯示
├── 考題（QuizView）
├── 造卡（CardMakerView）
├── 歷史（HistoryView）
└── 設定（SettingsView）
```

### 4.5 iPad 支援

SwiftUI 天然支援 iPad 響應式佈局，建議：
- 使用 `NavigationSplitView` 在 iPad 上提供側欄導覽
- 寬度足夠時可顯示更多卡片資訊（與 macOS 520px popover 類似的佈局）

---

## 五、Package.swift 需要的變更

```swift
platforms: [
    .macOS(.v14),
    .iOS(.v17)   // 新增
],
```

新增 iOS app target：

```swift
.executableTarget(
    name: "JapaneseLearningCardIOS",
    dependencies: ["JapaneseLearningCardCore"],
    // 不依賴 Sparkle，不需要 AppKit linkerSettings
)
```

---

## 六、可行性評估總結

| 評估面向 | 結果 |
|---------|------|
| **技術可行性** | ✅ 高 |
| **程式碼重用率** | ~70%（Core library 全部可用） |
| **UI 重寫工作量** | 中等（入口架構 + 平台型別替換） |
| **背景任務挑戰** | ✅ 已簡化（改為前景觸發） |
| **推播通知** | 暫緩，v1.0 不實作 |
| **跨裝置同步** | ✅ CloudKit 直接支援 |
| **App Store 上架門檻** | 需付費 Apple Developer 帳號（已有） |

**結論：建議開發。** 在定時推播暫緩、爬蟲改前景觸發的前提下，iOS 版本的實作複雜度大幅降低，主要工作量集中在 UI 層的重新包裝（入口 App 架構 + SwiftUI view 的 macOS 型別替換），不需要修改任何核心業務邏輯。

---

## 七、建議開發步驟

1. `Package.swift` 新增 `.iOS(.v17)` 平台宣告
2. 新建 `Sources/JapaneseLearningCardIOS` target（SwiftUI App lifecycle 入口）
3. 將 `RootView.swift` 中平台無關的 SwiftUI view 抽取為共用元件
4. 替換 macOS 專屬型別（`NSColor` → SwiftUI 原生，移除固定寬度）
5. 移除 `PresentationDetector`、`Updater`、Sparkle 依賴
6. 前景觸發爬蟲：`onAppear` / 手動按鈕取代排程背景任務
7. 整合 CloudKit 同步（現有邏輯直接可用）
8. 定時推播（後續版本）：`UNUserNotificationCenter` + WidgetKit
