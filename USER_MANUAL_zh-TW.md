# Japanese Learning Card 使用說明書

Japanese Learning Card 是一個 macOS 選單列日文學習工具。它可以定期顯示日文單字卡、從網頁或 AI 文章產生學習卡，並用 AI 產生選擇題讓你複習。

## 1. 啟動程式

在專案目錄執行：

```sh
swift run JapaneseLearningCard
```

程式啟動後會出現在 macOS 選單列，不會顯示在 Dock。點選選單列圖示即可開啟主視窗。

## 2. 主要分頁

主視窗上方有幾個分頁：

- 卡片：查看目前要複習的單字卡。
- 考題：讓 AI 根據已儲存的學習卡出選擇題。
- 造卡：貼上文章或單字清單，讓 AI 產生學習卡；也可以產生 AI 文章。
- 設定：設定顯示頻率、快速複習、AI Provider、資料來源、同步與 log。
- 歷史：查看已產生文章、已複習卡片與考試紀錄。

## 3. 設定 AI Provider

第一次使用 AI 功能前，需要先設定 Provider。

1. 打開「設定」分頁。
2. 在「AI Provider」區塊選擇 Provider。
3. 確認 Base URL。
4. 選擇或輸入 Model。
5. 輸入 API key。
6. 按「驗證並儲存」。

驗證成功後，API key 會存進 macOS Keychain，不會存在設定檔或 SQLite 資料庫中。

注意：「驗證並儲存」主要確認 API key、Base URL、Provider models API 可用。它不保證每一個模型的長時間生成都一定不會逾時；如果遇到逾時，可以查看 AI Log。

## 4. 新增網頁內容來源

你可以加入網頁 URL，讓 app 定期爬取內容並產生日文學習卡。

1. 打開「設定」分頁。
2. 在「內容來源」區塊輸入網址。
3. 按加號按鈕新增。
4. 按「手動更新」立即抓取，或等待排程自動更新。

每個來源旁邊有開關，可以暫停或啟用該來源。

## 5. 使用單字卡

打開「卡片」分頁可以看到目前要複習的卡片。

卡片通常包含：

- 單字
- 讀音
- 詞性
- JLPT 等級
- 中文意思
- 文法說明
- 日文例句
- 例句平假名
- 中文翻譯

你可以把卡片標記為已學會、略過，或繼續保留在複習中。app 會優先顯示新卡片，再顯示較久沒複習的卡片。

卡片上的「複製」按鈕位於單字區右上角，不會影響主要單字置中。卡片底部的光棒代表目前卡片剩餘時間；滑鼠停在畫面上時，計時會暫停，滑鼠移開後繼續。

### 快速複習

在「卡片」分頁右上方可以按「快速複習」開始短時間集中複習。

預設規則：

- 總時間：3 分鐘。
- 換卡間隔：20 秒。
- 滑鼠停在畫面上時，總時間與換卡倒數都會暫停。
- 按「下一張」會立刻換卡，並把該張卡的倒數補滿。
- 時間到會停止快速複習，畫面保留在目前卡片。

可以在「設定」→「顯示」調整：

- 快速複習時間。
- 快速換卡秒數。

## 6. 產生 AI 文章

「造卡」分頁中的 AI 文章功能可以讓 AI 產生日文短文，再自動擷取單字卡。

使用方式：

1. 打開「造卡」分頁。
2. 選擇目標 JLPT 等級。
3. 可選擇輸入主題，例如「旅行-京都」。
4. 按「立即產生文章」。

如果主題留空，AI 會自行選擇生活化主題。

你也可以啟用週期產生：

1. 在「自動排程」打開「啟用週期產生」。
2. 設定週期，例如每 12 小時產生一次。

產生成功後，文章會出現在「歷史」分頁的「AI 文章」中，文章擷取出的單字卡也會加入卡片庫。

## 7. AI 考題

「考題」分頁可以讓 AI 根據目前已儲存的學習卡產生選擇題。

使用方式：

1. 打開「考題」分頁。
2. 按「AI 出題」。
3. 等待題目產生。
4. 選擇答案。
5. 查看正解與繁體中文解析。
6. 按「下一題」繼續作答。

答題結果會被保存，之後可以在「歷史」分頁的「考試紀錄」中回看。

## 8. 查看歷史紀錄

「歷史」分頁包含：

- AI 文章：查看已產生的 AI 日文文章。
- 複習卡片：查看曾經顯示過的卡片與複習時間。
- 考試紀錄：查看已作答或略過的考題、答對率、你的答案、正解與解析。

考試紀錄會累積保存，適合之後針對答錯題目重新複習。

## 9. 查看資料庫

目前資料主要透過「設定」與「歷史」查看；開發或除錯時可在「設定」匯出 SQLite 資料庫。

可回看的內容包含：

- 來源與同步狀態：在「設定」查看。
- AI 文章、複習卡片、考題紀錄：在「歷史」查看。

## 10. AI Log

如果 AI 呼叫失敗、逾時，或想查看速度，可以打開 AI Log。

1. 打開「設定」分頁。
2. 找到「AI Log」區塊。
3. 按「開啟 AI Log」。

Log 檔案格式是 JSONL，一行代表一次 AI/API 呼叫。常見欄位：

- timestamp：呼叫時間。
- operation：呼叫用途，例如 `generateArticle`、`generateCards`、`generateQuiz`。
- endpoint：Provider API 位置。
- model：使用的模型。
- statusCode：HTTP 狀態碼。
- durationMilliseconds：花費時間。
- requestBytes：請求大小。
- responseBytes：回應大小。
- promptTokens：輸入 token 數，Provider 有回傳時才會出現。
- completionTokens：輸出 token 數，Provider 有回傳時才會出現。
- tokensPerSecond：輸出吞吐，Provider 有回 token usage 時才會出現。
- errorSummary：失敗原因摘要。

如果看到 `The request timed out.`，代表 Provider 在 timeout 時間內沒有完成回應，不一定是 API key 錯誤。API key 錯誤通常會看到 401 或 403 類型的 HTTP 錯誤。

## 11. 資料儲存位置

> **iCloud 同步需要用 Developer ID 簽名的正式版本**(見 [DEVELOPMENT.md](./DEVELOPMENT.md) 的 iCloud 設定)。ad-hoc、`swift run`，或 `LOCAL_BUILD=1` 的本機 UI 驗證版本會停用 iCloud / CloudKit 同步，避免測試畫面時影響雲端資料。

app 會使用本機 SQLite 資料庫：

```text
~/Library/Application Support/JapaneseLearningCard/store.sqlite
```

正式 Developer ID 版本會透過 CloudKit 同步整份資料快照；本機 UI 驗證版本不會 pull 或 push iCloud 資料。

API key 會存放在 macOS Keychain。

AI request log 通常位於：

```text
~/Library/Application Support/JapaneseLearningCard/ai-requests.jsonl
```

## 12. 常見問題

### 驗證成功，但 AI 生成還是失敗？

驗證成功代表 key 和 Provider 基本連線可用。長文章生成、單字擷取或考題生成仍可能因模型太慢、Provider 負載、格式不相容或 timeout 失敗。請先查看 AI Log 的 `operation`、`statusCode` 和 `errorSummary`。

### Log 裡沒有 statusCode，只有 timeout？

這通常代表請求還沒收到 HTTP 回應就逾時了，不是 Provider 回了錯誤碼。可以稍後重試，或換較快模型。

### AI 沒有照 JSON 格式回應？

在「設定」的「JSON 格式輸出」可以調整。OpenAI 官方模型通常建議使用 JSON 物件；有些第三方 endpoint 不支援 `response_format`，這時需要關閉。

### 為什麼沒有新卡片？

可能原因：

- 內容來源沒有啟用。
- 網頁抓取失敗。
- AI 沒有產生有效卡片。
- 模型產生的卡片被判定為 N5 並被略過。
- 內容與既有資料重複。

可以查看「設定」中的來源錯誤訊息，或打開 AI Log 檢查 AI 呼叫結果。

## 13. 建議使用流程

1. 在「設定」完成 AI Provider 驗證。
2. 到「造卡」產生第一篇 AI 文章或手動單字卡。
3. 到「卡片」開始複習單字。
4. 想集中記憶時，在「卡片」啟動快速複習。
5. 到「考題」產生 AI 選擇題並作答。
6. 到「歷史」查看複習卡片與考試紀錄。
7. 若 AI 呼叫異常，到「設定」打開 AI Log 檢查原因。
