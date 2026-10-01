# 單字卡加入時間顯示與 CloudKit 暫態錯誤自動重試設計規格

## 1. 概述 (Overview)

本規格針對使用者提出之兩項需求進行設計與實作：
1. **單字卡左下角增加顯示加入時間**：格式為 `出現 X 次 · YYYY-MM-DD`。若卡片缺少建立時間或為無效初始值（如 Unix epoch 1970 等），自動補齊為當日日期並落盤寫入儲存庫。
2. **CloudKit 同步錯誤修復與優化**：處理 `pushFailed("backing(...Service Unavailable (6/2009)...Retry after 4.0 seconds...)")` 錯誤。增加暫態錯誤（Service Unavailable / Rate Limited / Zone Busy）的指數退避自動重試機制，並美化錯誤訊息。

---

## 2. 功能細節設計 (Detailed Design)

### 2.1 單字卡加入時間顯示與補齊 (Card Creation Date Display & Backfill)

#### 2.1.1 顯示格式
- **位置**：[`Sources/JapaneseLearningCardUI/RootView.swift`](file:///Users/jason/workspace/japanese-learning-card/Sources/JapaneseLearningCardUI/RootView.swift) 的 `CardActionBar`。
- **樣式**：
  ```swift
  Text("出現 \(card.shownCount) 次 · \(card.formattedCreatedAt)")
      .font(.caption)
      .foregroundStyle(.secondary)
  ```
- **格式規範**：`yyyy-MM-dd`（例如 `2026-10-01`）。

#### 2.1.2 模型與有效性校正
- 在 [`Sources/JapaneseLearningCardCore/Models.swift`](file:///Users/jason/workspace/japanese-learning-card/Sources/JapaneseLearningCardCore/Models.swift)：
  - `LearningCard.createdAt: Date`。
  - 新增屬性或格式化輔助：
    ```swift
    public var formattedCreatedAt: String {
        Self.dateFormatter.string(from: createdAt)
    }
    ```
  - 新增有效性檢驗方法 `isValidCreatedAt`（檢查是否晚於 1970-01-02）。
  - 若在 JSON 解碼或載入時發現 `createdAt` 為空或小於等於 1970-01-02，則自動設定為 `Date()`（當前日期與時間）。

#### 2.1.3 資料持久化補全 (Persistence Backfill)
- 在 [`Sources/JapaneseLearningCardCore/AppStore.swift`](file:///Users/jason/workspace/japanese-learning-card/Sources/JapaneseLearningCardCore/AppStore.swift) 載入 `loadRows` 或 `read()` 時：
  - 檢測是否有卡片的 `createdAt` 被自動補齊。
  - 若有卡片日期被修正，自動在背景觸發 update 將校正後之卡片存回 SQLite，確保跨裝置同步與永久儲存。

---

### 2.2 CloudKit 暫態錯誤處理與重試機制 (CloudKit Transient Error Retry & Handling)

#### 2.2.1 錯誤型別擴充
- 在 [`Sources/JapaneseLearningCardCore/CloudKitV2Schema.swift`](file:///Users/jason/workspace/japanese-learning-card/Sources/JapaneseLearningCardCore/CloudKitV2Schema.swift) 中擴充 `CloudKitV2BackingError`：
  ```swift
  public enum CloudKitV2BackingError: Error, Sendable, Equatable {
      case networkUnavailable
      case quotaExceeded
      case notAuthenticated
      case recordTooLarge
      case changeTokenExpired
      case serviceUnavailable(retryAfter: TimeInterval?)
      case rateLimited(retryAfter: TimeInterval?)
      case zoneBusy
      case partialBatchFailure(String)
      case unknown(String)
  }
  ```

#### 2.2.2 錯誤轉換 (Error Translation)
- 在 [`Sources/JapaneseLearningCardCore/CloudKitV2Backing.swift`](file:///Users/jason/workspace/japanese-learning-card/Sources/JapaneseLearningCardCore/CloudKitV2Backing.swift) 之 `translate(_ error: Error)`：
  - 識別 `CKError.serviceUnavailable` (code 6) 並提取 `error.retryAfterSeconds`。
  - 識別 `CKError.requestRateLimited` (code 7) 並提取 `error.retryAfterSeconds`。
  - 識別 `CKError.zoneBusy` (code 23)。

#### 2.2.3 底層自動重試 (Backoff & Retry Runner)
- 在 `CKContainerV2Backing` 中加入執行輔助：
  ```swift
  func withRetry<T: Sendable>(
      maxAttempts: Int = 3,
      operation: @Sendable () async throws -> T
  ) async throws -> T
  ```
  - 當捕獲到 `serviceUnavailable` 或 `rateLimited` 或 `zoneBusy` 時：
    - 等待時間：優先使用 `retryAfter` 秒數（若無則預設 3.0 秒），加上 0.1~0.5 秒隨機抖動 (jitter)。
    - 若嘗試次數小於 `maxAttempts`（共 3 次），執行 `try await Task.sleep(nanoseconds: ...)` 後重試。
    - 超過重試次數則拋出對應的 `CloudKitV2BackingError`。
  - 將 `save(items:)`、`fetchChanges(since:)`、`ensureZone()` 包裝在 `withRetry` 內執行。

#### 2.2.4 友善 UI 錯誤呈現 (User-Friendly UI Error Presentation)
- 在 [`Sources/JapaneseLearningCardUI/AppViewModel.swift`](file:///Users/jason/workspace/japanese-learning-card/Sources/JapaneseLearningCardUI/AppViewModel.swift)：
  - 改善 `iCloudLastErrorMessage` 之顯示文字：
    - 若包含 `serviceUnavailable` 或 `503` 或 `Service Unavailable`：轉換為「iCloud 伺服器暫時忙碌，稍後將自動重試」。
    - 若包含 `networkUnavailable` 或 `networkFailure`：轉換為「網路連線中斷，恢復連線後將自動同步」。
    - 若包含 `notAuthenticated`：轉換為「未登入 iCloud，請檢查系統設定中的 Apple 帳號」。
    - 若包含 `quotaExceeded`：轉換為「iCloud 儲存空間已滿」。

---

## 3. 測試與驗證計畫 (Testing & Verification)

1. **單元測試 (Unit Tests)**：
   - 驗證缺少 `createdAt` 的 JSON 能夠解碼為當前日期。
   - 驗證 `formattedCreatedAt` 輸出正確格式 `yyyy-MM-dd`。
   - 驗證 `CKError.serviceUnavailable` 正確轉換為 `CloudKitV2BackingError.serviceUnavailable` 且保留 `retryAfter`。
   - 驗證重試器在模擬暫態錯誤時能正確重試至成功。
2. **整合驗證 (Integration Checks)**：
   - 執行 `PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift run JapaneseLearningCardCoreChecks`。
   - 執行 `PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test`。
