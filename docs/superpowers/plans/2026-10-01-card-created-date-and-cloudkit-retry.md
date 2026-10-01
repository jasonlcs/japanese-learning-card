# 單字卡加入時間顯示與 CloudKit 暫態重試實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在單字卡左下角顯示格式為 `出現 X 次 · YYYY-MM-DD` 的加入時間（無值時自動補為當天日期並持久化），並為 CloudKit 同步新增暫態錯誤（Service Unavailable / Rate Limited）的退避自動重試與友善錯誤提示。

**Architecture:**
1. 在 `LearningCard` 擴充 `formattedCreatedAt` 與日期校正邏輯，`AppStore` 載入時自動修正無效/過舊日期並寫回 SQLite。
2. 擴充 `CloudKitV2BackingError`，在 `CKContainerV2Backing` 實作依據 `retryAfterSeconds` 的 `withRetry` 重試執行器（上限 3 次），並在 `AppViewModel` 將同步錯誤轉為繁體中文友善提示。
3. 在 `CardActionBar` 調整 UI 呈現。

**Tech Stack:** Swift 6, SwiftUI, CloudKit, SQLite3, Swift Testing / XCTest.

## Global Constraints
- macOS 14+ / iOS 17+。
- 專案建置與測試需指定 Xcode 工具鏈：`PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH`。
- 單字卡左下角顯示格式嚴格遵守：`出現 \(card.shownCount) 次 · \(card.formattedCreatedAt)`（日期格式為 `yyyy-MM-dd`）。

---

### Task 1: LearningCard 模型擴充建立時間格式化與校正

**Files:**
- Modify: `Sources/JapaneseLearningCardCore/Models.swift`
- Test: `Tests/JapaneseLearningCardCoreTests/RubySupportTests.swift` (或新增 `Tests/JapaneseLearningCardCoreTests/CardModelTests.swift`)

**Interfaces:**
- Produces: `LearningCard.formattedCreatedAt: String`, `LearningCard.sanitizedCreatedAt(Date) -> Date`

- [ ] **Step 1: 撰寫測試驗證 `formattedCreatedAt` 與日期校正**
  建立 `Tests/JapaneseLearningCardCoreTests/CardModelTests.swift`：
  - 測試正常日期輸出格式為 `yyyy-MM-dd`。
  - 測試 Unix epoch (`1970-01-01`) 或更早之日期經解碼或校正後自動補為今日（不早於當前日期的有效範圍）。

- [ ] **Step 2: 執行測試並確認測試因尚未實作而失敗**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter CardModelTests
  ```

- [ ] **Step 3: 在 `Models.swift` 中實作 `formattedCreatedAt` 與解碼檢查**
  - 新增線程安全的靜態 `DateFormatter`（格式 `yyyy-MM-dd`，時區設為 `current`，calendar 設為 Gregorian）。
  - 在 `init(from decoder:)` 中，若解碼出的日期小於等於 `Date(timeIntervalSince1970: 86400)`，自動賦值為 `Date()`。
  - 新增計算屬性 `public var formattedCreatedAt: String { Self.createdDateFormatter.string(from: createdAt) }`。

- [ ] **Step 4: 執行測試確認通過**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter CardModelTests
  ```

- [ ] **Step 5: 提交變更**
  ```bash
  git add Sources/JapaneseLearningCardCore/Models.swift Tests/JapaneseLearningCardCoreTests/CardModelTests.swift
  git commit -m "feat(core): add formattedCreatedAt and auto-backfill for invalid dates in LearningCard"
  ```

---

### Task 2: AppStore 自動修補無效卡片日期並持久化

**Files:**
- Modify: `Sources/JapaneseLearningCardCore/AppStore.swift`
- Test: `Tests/JapaneseLearningCardCoreTests/AppStoreDateBackfillTests.swift`

**Interfaces:**
- Consumes: `LearningCard.formattedCreatedAt`, `LearningCard.createdAt`
- Produces: `AppStore.loadSnapshot()` 自動校正並存回 SQLite

- [ ] **Step 1: 撰寫 AppStore 載入修補測試**
  撰寫 `AppStoreDateBackfillTests.swift`：
  - 手動寫入一筆 `createdAt` 為 `1970-01-01` 或缺少欄位的卡片到臨時資料庫。
  - 呼叫 `AppStore` 初始化 / `read()`，驗證載入後的卡片 `createdAt` 已被自動校正為當日。
  - 重新從資料庫讀取，確認已被持久化儲存。

- [ ] **Step 2: 執行測試確認失敗**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter AppStoreDateBackfillTests
  ```

- [ ] **Step 3: 實作 AppStore 載入時之卡片日期檢查與背景儲存**
  在 `AppStore.loadSnapshot()` 或載入 `learning_cards` 時：
  - 檢查是否有卡片的 `createdAt` 小於等於 `Date(timeIntervalSince1970: 86400)`。
  - 若有，校正為 `Date()`，並非同步觸發 `self.update` 將更新寫回 SQLite。

- [ ] **Step 4: 執行測試確認通過**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter AppStoreDateBackfillTests
  ```

- [ ] **Step 5: 提交變更**
  ```bash
  git add Sources/JapaneseLearningCardCore/AppStore.swift Tests/JapaneseLearningCardCoreTests/AppStoreDateBackfillTests.swift
  git commit -m "feat(core): auto-persist corrected card creation dates on load in AppStore"
  ```

---

### Task 3: CloudKit V2 暫態錯誤分類與自動退避重試

**Files:**
- Modify: `Sources/JapaneseLearningCardCore/CloudKitV2Schema.swift`
- Modify: `Sources/JapaneseLearningCardCore/CloudKitV2Backing.swift`
- Test: `Tests/JapaneseLearningCardCoreTests/CloudKitRetryTests.swift`

**Interfaces:**
- Consumes: `CKError`, `CKError.Code.serviceUnavailable`, `CKError.Code.requestRateLimited`, `CKError.Code.zoneBusy`
- Produces: `CloudKitV2BackingError.serviceUnavailable`, `CloudKitV2BackingError.rateLimited`, `CloudKitV2BackingError.zoneBusy`
- Produces: `CKContainerV2Backing.withRetry<T>(maxAttempts:operation:)`

- [ ] **Step 1: 撰寫 CloudKit 錯誤轉換與重試邏輯測試**
  撰寫 `CloudKitRetryTests.swift`：
  - 驗證 `CKContainerV2Backing.translate` 在收到 `serviceUnavailable` 時能正確提取 `retryAfterSeconds`。
  - 驗證重試輔助函數：模擬前兩次丟出 `serviceUnavailable`，第三次成功，驗證重試成功並回傳結果。
  - 驗證超過最大重試次數後正確拋出 `CloudKitV2BackingError.serviceUnavailable`。

- [ ] **Step 2: 執行測試確認失敗**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter CloudKitRetryTests
  ```

- [ ] **Step 3: 擴充 CloudKitV2Schema 與 CloudKitV2Backing**
  - 在 `CloudKitV2Schema.swift` 新增 `serviceUnavailable(retryAfter: TimeInterval?)`、`rateLimited(retryAfter: TimeInterval?)`、`zoneBusy`。
  - 在 `CloudKitV2Backing.swift` 的 `translate` 函數處理這些 code，並由 `error.retryAfterSeconds` 提取等待秒數。
  - 在 `CKContainerV2Backing` 實作 `withRetry`：
    - 遇到暫態錯誤且 `attempt < maxAttempts` 時，計算延遲時間（`retryAfter ?? 3.0` + 隨機 jitter 0.1~0.4s），執行 `Task.sleep` 後重試。
  - 在 `save(items:)`、`fetchChanges(since:)`、`ensureZone()` 中套用 `withRetry`。

- [ ] **Step 4: 執行測試確認通過**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test --filter CloudKitRetryTests
  ```

- [ ] **Step 5: 提交變更**
  ```bash
  git add Sources/JapaneseLearningCardCore/CloudKitV2Schema.swift Sources/JapaneseLearningCardCore/CloudKitV2Backing.swift Tests/JapaneseLearningCardCoreTests/CloudKitRetryTests.swift
  git commit -m "feat(sync): add retry runner for transient CloudKit errors"
  ```

---

### Task 4: UI 更新（單字卡底欄加入時間顯示與 iCloud 錯誤訊息友善化）

**Files:**
- Modify: `Sources/JapaneseLearningCardUI/RootView.swift`
- Modify: `Sources/JapaneseLearningCardUI/AppViewModel.swift`

**Interfaces:**
- Consumes: `LearningCard.formattedCreatedAt`, `CloudKitV2BackingError`
- Produces: `CardActionBar` 中的 `出現 \(card.shownCount) 次 · \(card.formattedCreatedAt)`
- Produces: `AppViewModel.iCloudUserFriendlyErrorMessage`

- [ ] **Step 1: 在 `AppViewModel.swift` 實作友善錯誤轉換**
  在 `AppViewModel.swift` 新增輔助方法 `userFriendlySyncErrorMessage(from error: Error) -> String`：
  - 若包含 `serviceUnavailable` 或 `503` 或 `Service Unavailable`：回傳「iCloud 伺服器暫時忙碌，稍後將自動重試」。
  - 若包含 `networkUnavailable` 或 `networkFailure`：回傳「網路連線中斷，恢復連線後將自動同步」。
  - 若包含 `notAuthenticated`：回傳「未登入 iCloud，請檢查系統設定中的 Apple 帳號」。
  - 若包含 `quotaExceeded`：回傳「iCloud 儲存空間已滿」。
  - 其他情況回傳格式簡化後的說明文字。
  - 在 `performSync()` 中賦值 `iCloudLastErrorMessage = userFriendlySyncErrorMessage(from: error)`。

- [ ] **Step 2: 在 `RootView.swift` 更新 `CardActionBar`**
  將行 1133 的：
  ```swift
  Text("出現 \(card.shownCount) 次")
      .font(.caption)
      .foregroundStyle(.secondary)
  ```
  修改為：
  ```swift
  Text("出現 \(card.shownCount) 次 · \(card.formattedCreatedAt)")
      .font(.caption)
      .foregroundStyle(.secondary)
  ```

- [ ] **Step 3: 建置並驗證 UI 編譯無誤**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift build
  ```

- [ ] **Step 4: 提交變更**
  ```bash
  git add Sources/JapaneseLearningCardUI/RootView.swift Sources/JapaneseLearningCardUI/AppViewModel.swift
  git commit -m "feat(ui): display formattedCreatedAt in CardActionBar and user-friendly iCloud errors"
  ```

---

### Task 5: 完整整合驗證與檢查

**Files:**
- Verify across all modified components

- [ ] **Step 1: 執行完整核心檢查**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift run JapaneseLearningCardCoreChecks
  ```

- [ ] **Step 2: 執行完整單元測試套件**
  ```bash
  PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH swift test
  ```

- [ ] **Step 3: 驗證無殘留編譯警告與未提交檔案**
  ```bash
  git status
  ```
