# 開發與發佈

## iCloud 同步設定

`Sources/JapaneseLearningCard/JapaneseLearningCard.entitlements` 與 `Info.plist` 的 `NSUbiquitousContainers` 都已經填好 bundle id `io.github.jasonlcs.japaneselearningcard` 對應的 container `iCloud.io.github.jasonlcs.japaneselearningcard`。要讓 iCloud 真的跑起來，還需要在 Apple Developer Portal 註冊對應資源：

1. **付費 Apple Developer 帳號**($99/年)。免費帳號無法建立 iCloud container。
2. 進入 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)：
   - 建立 App ID `io.github.jasonlcs.japaneselearningcard`(若已存在請編輯)
   - 在 Capability 勾選 **iCloud → Cloud Documents**
3. 在同一頁的 Containers 分頁建立 container `iCloud.io.github.jasonlcs.japaneselearningcard`，並把上一步的 App ID 關聯上去。
4. 用 Xcode 或 Developer Portal 重新產生 / 下載 **Developer ID Application** 憑證(需要該憑證隸屬於上一步的 team)。
5. 本機建置時帶 `SIGNING_IDENTITY`，build-app.sh 會把 entitlement 簽進去：

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.sh
```

> ad-hoc 簽名(`./build-app.sh` 不帶 `SIGNING_IDENTITY`)雖然會把 entitlement 寫進去，但系統會在 runtime 拒絕 iCloud 存取，只是給本機 UI 測試用。

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
