# Release 流程

## 本地 Developer ID 簽名 + Notarization

```bash
# 1. 建立含 iCloud 同步的 Developer ID 簽名版
SIGNING_IDENTITY="Developer ID Application: WAFERLOCK Corp. (QXYXY39U4Q)" ./build-app.sh

# 2. 送交 Apple Notarization
xcrun notarytool submit ".build/app/JapaneseLearningCard.dmg" \
  --keychain-profile "JapaneseLearningCard" --wait

# 3. Staple ticket
xcrun stapler staple ".build/app/JapaneseLearningCard.app"
xcrun stapler staple ".build/app/JapaneseLearningCard.dmg"
```

## 需求檔案

以下檔案**不要 commit 進 repo**（已在 `.gitignore` 中）：

| 檔案 | 用途 |
|------|------|
| `DeveloperID.p12` | Developer ID 憑證（含私鑰） |
| `JapaneseLearningCard_DeveloperID.provisionprofile` | Developer ID Provisioning Profile |

## GitHub Release (CI/CD)

### 前置：設定 Repository Secrets

前往 GitHub repo → **Settings → Secrets and variables → Actions**，新增：

| Secret | 說明 |
|--------|------|
| `DEVELOPER_CERTIFICATE_BASE64` | `base64 < DeveloperID.p12` 的輸出 |
| `CERTIFICATE_PASSWORD` | .p12 匯出時設的密碼 |
| `DEVELOPER_PROVISIONING_PROFILE_BASE64` | `base64 < JapaneseLearningCard_DeveloperID.provisionprofile` 的輸出 |
| `APPLE_ID` | Apple ID 信箱 |
| `APPLE_APP_PASSWORD` | 從 appleid.apple.com 產生的 App-Specific Password |
| `APPLE_TEAM_ID` | Team ID (`QXYXY39U4Q`) |

### 發佈 Release

```bash
git tag -a v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

CI 會自動：

1. 匯入 Developer ID 憑證 + Provisioning Profile
2. Build `.app` + `.dmg`
3. 送交 Apple Notarization
4. Staple ticket
5. 上傳 `.dmg` 到 GitHub Release

### 純 CI 測試（不簽名）

若未設定 signing secrets，CI 會自動降級為 ad-hoc 簽名（無 iCloud 同步）。

## Sparkle 自動更新（app 內直接更新）

App 透過 [Sparkle](https://sparkle-project.org) 在 app 內下載、驗證、安裝新版並重開。
更新 feed（`appcast.xml`）放在 **GitHub Pages**，更新檔用一組 **EdDSA 金鑰**簽章。

### 一次性設定

1. **產生 EdDSA 金鑰**（本機跑一次，私鑰會存進 login keychain）：

   ```bash
   # 下載對應版本的 Sparkle 工具（與 Package.swift 解析到的版本一致，目前 2.9.3）
   curl -fsSL https://github.com/sparkle-project/Sparkle/releases/download/2.9.3/Sparkle-2.9.3.tar.xz | tar -xJ
   ./bin/generate_keys
   # 會印出 public key（base64），並把 private key 存進 keychain
   ```

2. **填入公鑰**：把印出的 public key 貼到 `Sources/JapaneseLearningCard/Info.plist`
   的 `SUPublicEDKey`（取代 `__SPARKLE_PUBLIC_KEY__`）。
   也可以改設成 repo secret `SPARKLE_PUBLIC_KEY`，CI 會在 build 時自動注入。

3. **匯出私鑰給 CI**：

   ```bash
   ./bin/generate_keys -x sparkle_private_key.pem   # 匯出私鑰
   ```

   把 `sparkle_private_key.pem` 內容存成 repo secret **`SPARKLE_PRIVATE_KEY`**，
   然後刪掉本機檔案（**不要 commit**）。

4. **開啟 GitHub Pages**：repo → Settings → Pages → Source 選 `gh-pages` branch
   （第一次跑完 release CI 後該 branch 才會出現；可先手動建立空 branch）。
   feed 網址即 `https://jasonlcs.github.io/japanese-learning-card/appcast.xml`
   （已寫死在 Info.plist 的 `SUFeedURL`）。

### Secrets 一覽（除前述簽名/公證外，新增）

| Secret | 說明 |
|--------|------|
| `SPARKLE_PRIVATE_KEY` | `generate_keys -x` 匯出的 EdDSA 私鑰（PEM 內容） |
| `SPARKLE_PUBLIC_KEY` | （可選）EdDSA 公鑰，未直接寫進 Info.plist 時由 CI 注入 |

### 之後每次發版

照常 `git tag -a vX.Y.Z` + `git push`。release CI 會在 build/公證/上傳 DMG 後，
自動產生簽章過的 `appcast.xml` 並發佈到 `gh-pages`，使用者 app 就能收到更新。
