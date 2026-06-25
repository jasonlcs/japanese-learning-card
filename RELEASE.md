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
