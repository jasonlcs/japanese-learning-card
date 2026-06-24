# 開發與發佈

## iCloud 同步設定 (CloudKit Private Database)

`Sources/JapaneseLearningCard/JapaneseLearningCard.entitlements` 已經填好 bundle id `io.github.jasonlcs.japaneselearningcard` 對應的 container `iCloud.io.github.jasonlcs.japaneselearningcard`, 走的是 CloudKit Private Database (不是 iCloud Drive 檔案同步)。要在 Apple Developer Portal 註冊對應資源:

1. **付費 Apple Developer 帳號**($99/年)。免費帳號無法建立 iCloud container。
2. 進入 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list):
   - 建立/編輯 App ID `io.github.jasonlcs.japaneselearningcard`
   - 在 Capability 勾選 **iCloud → CloudKit** (不是 Cloud Documents, 那是 iCloud Drive 用的)
   - 在同個 Capability 勾 **App Groups** (Pelu 模式需要, 為之後 extension 預留; 沒勾也不影響目前功能)
3. 在同一頁的 iCloud Containers 分頁建立 container `iCloud.io.github.jasonlcs.japaneselearningcard`, 確認關聯到上一步的 App ID。
4. 用 Xcode 或 Developer Portal 重新產生 / 下載 **Developer ID Application** 憑證(必須隸屬於上一步的 team, 跨 team 憑證會被 Apple 拒絕)。
5. 本機建置時帶 `SIGNING_IDENTITY`, build-app.sh 會把 entitlement 簽進去:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.sh
```

> ad-hoc 簽名(`./build-app.sh` 不帶 `SIGNING_IDENTITY`)雖然會把 entitlement 寫進去, 但系統會在 runtime 拒絕 iCloud 存取, 只是給本機 UI 測試用。Settings 的 iCloud 區塊會顯示「未登入 iCloud」, app 退回純本地模式。

### 同步架構

- 整包 `AppSnapshot` 序列化進 1 筆 CloudKit record (`AppDatabase/database`)
- macOS 的 silent push 不可靠, 同步採「**foreground pull + 60s 保底 poll + silent push 期待醒**」三路:
  - App 啟動 / 進入前景 → `AppDelegate.applicationDidBecomeActive` 觸發 pull
  - 60s timer → `AppViewModel.scheduleSyncPollTimer` 保底 pull
  - silent push → `AppDelegate.application(_:didReceiveRemoteNotification:)` 觸發 pull
- 任何 snapshot 變化 (本地寫入) → debounce 500ms 推到雲端
- 推送走樂觀鎖 (recordChangeTag), 撞 conflict 由 `CloudKitTransport` 自動 retry 一次
- Pull 結果跟 local + synced base 跑 **3-way merge** (`Merger.merge3Way`), 衝突寫進 `ConflictStore` 給 settings 紅點, 未衝突的 LWW 自動解掉

### 跨裝置同步流程 (使用者視角)

1. 公司 Mac 改了一張卡 → 本地 SQLite 寫入 → debounce push → CloudKit record 更新
2. CloudKit 發 silent push 給所有訂閱的裝置 (含家裡 Mac)
3. 家裡 Mac 收到 silent push → `AppDelegate` 轉發 → `AppViewModel.performPull` → 3-way merge → 本地 SQLite 更新 → UI reload
4. macOS push 不可靠時, 60s 保底 poll 會抓到差異

## 本機建置 `.app` 和 DMG

```bash
chmod +x build-app.sh
./build-app.sh
```

產出位於 `.build/app/`：

- `JapaneseLearningCard.app`
- `JapaneseLearningCard.dmg`

未設定 `SIGNING_IDENTITY` 時會使用 ad-hoc 簽名，適合本機測試。

## Developer ID 簽名

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.sh
```

腳本會使用 hardened runtime：

```bash
codesign --deep --force --options runtime --timestamp \
  --entitlements JapaneseLearningCard.app/Contents/JapaneseLearningCard.entitlements \
  --sign "$SIGNING_IDENTITY" JapaneseLearningCard.app
```

## GitHub Actions 公證

推送 `v*` tag 會觸發 `.github/workflows/release.yml`：

```bash
git tag v0.1.0
git push origin v0.1.0
```

需要在 GitHub repo secrets 設定：

| Secret | 說明 |
|---|---|
| `DEVELOPER_CERTIFICATE_BASE64` | Developer ID Application `.p12` 的 base64 |
| `CERTIFICATE_PASSWORD` | `.p12` 匯出密碼 |
| `APPLE_ID` | Apple ID email |
| `APPLE_APP_PASSWORD` | App-specific password |
| `APPLE_TEAM_ID` | Apple Developer Team ID |

CI 會：

1. 匯入 Developer ID 憑證到暫時 keychain
2. 執行 `build-app.sh`
3. 用 `xcrun notarytool submit --wait` 公證 DMG
4. 用 `xcrun stapler staple` 將票據釘到 DMG
5. 建立 GitHub Release 並上傳 DMG
