# 開發與發佈

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
codesign --deep --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" JapaneseLearningCard.app
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
