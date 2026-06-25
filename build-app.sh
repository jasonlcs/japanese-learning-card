#!/bin/bash
set -euo pipefail

PRODUCT="JapaneseLearningCard"
SRC="Sources/$PRODUCT"
BUILD_DIR=".build/app"
APP_BUNDLE="$BUILD_DIR/$PRODUCT.app"
STAGING="$BUILD_DIR/staging"
RESOURCES="$SRC/Resources"
ENTITLEMENTS="$SRC/$PRODUCT.entitlements"
ENTITLEMENTS_ADHOC="$SRC/$PRODUCT.entitlements.ad-hoc"
DMG_NAME="$PRODUCT.dmg"
DMG_FINAL="$BUILD_DIR/$DMG_NAME"

echo "▸ 編譯 release binary..."
# Developer ID 簽名 → 開 iCloud 同步 (會去 call CKContainer, 需要 restricted entitlement)
# ad-hoc 簽名 → 關 iCloud (沒 entitlement 的話 CKContainer.__allocating_init 會被 amfi kill)
SWIFT_FLAGS=""
if [ -n "${SIGNING_IDENTITY:-}" ]; then
    SWIFT_FLAGS="-Xswiftc -DICLOUD_ENABLED"
fi
swift build -c release --product "$PRODUCT" $SWIFT_FLAGS

echo "▸ 建立 .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

BIN_PATH="$(swift build -c release --show-bin-path)"
BINARY="$BIN_PATH/$PRODUCT"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$PRODUCT"
cp "$SRC/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -d "$RESOURCES" ] && [ "$(find "$RESOURCES" -type f | wc -l | tr -d ' ')" != "0" ]; then
    echo "▸ 複製 resources..."
    cp -R "$RESOURCES"/. "$APP_BUNDLE/Contents/Resources/"
fi

# Developer ID Provisioning Profile (for restricted entitlements like CloudKit)
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-${PRODUCT}_DeveloperID.provisionprofile}"
if [ -n "$SIGNING_IDENTITY" ] && [ -f "$PROVISIONING_PROFILE" ]; then
    echo "▸ 嵌入 provisioning profile: $PROVISIONING_PROFILE"
    cp "$PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"
elif [ -n "$SIGNING_IDENTITY" ] && [ ! -f "$PROVISIONING_PROFILE" ]; then
    echo "⚠️ 找不到 provisioning profile ($PROVISIONING_PROFILE)，iCloud 同步可能被 AMFI 拒絕"
fi

# 根據簽名類型選 entitlement 檔:
# - Developer ID 簽名 → 完整版, 含 com.apple.developer.icloud-* (restricted)
# - ad-hoc 簽名 → 精簡版, 不放 restricted entitlements (AMFI 會拒絕執行)
ENTITLEMENT_ARG=""
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [ -n "$SIGNING_IDENTITY" ]; then
    if [ -f "$ENTITLEMENTS" ]; then
        ENTITLEMENT_ARG="--entitlements $ENTITLEMENTS"
        echo "▸ 套用完整 entitlements (Developer ID 簽名): $ENTITLEMENTS"
    else
        echo "⚠️ 找不到 $ENTITLEMENTS，iCloud 同步會被系統拒絕"
    fi
else
    if [ -f "$ENTITLEMENTS_ADHOC" ]; then
        ENTITLEMENT_ARG="--entitlements $ENTITLEMENTS_ADHOC"
        echo "▸ 套用精簡 entitlements (ad-hoc 簽名, 無 iCloud): $ENTITLEMENTS_ADHOC"
    fi
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "▸ 使用 Developer ID 簽名 app: $SIGNING_IDENTITY"
    codesign --deep --force --options runtime --timestamp \
        $ENTITLEMENT_ARG \
        --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
else
    echo "▸ 用 ad-hoc 簽名 app (加 hardened runtime)..."
    # ad-hoc 簽名不能帶 restricted entitlements (AMFI 會直接 kill),
    # 所以 iCloud 相關 entitlement 拿掉, app 才能跑起來。
    # 想跑 iCloud 同步要 Developer ID 簽名版本。
    codesign --force --options runtime $ENTITLEMENT_ARG -s - "$APP_BUNDLE" 2>/dev/null || true
    # 清掉 quarantine / provenance xattr, 這樣 spctl 才不會擋
    xattr -cr "$APP_BUNDLE" 2>/dev/null || true
fi

echo "▸ 驗證 app 簽名..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" || true

echo "▸ 建立 DMG 暫存目錄..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "▸ 建立 DMG..."
rm -f "$DMG_FINAL"
hdiutil create -volname "$PRODUCT" -srcfolder "$STAGING" \
  -ov -format UDZO -imagekey zlib-level=9 \
  -scrub "$DMG_FINAL"

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "▸ 簽章 DMG..."
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_FINAL"
fi

echo "▸ 清理暫存..."
rm -rf "$STAGING"

echo "▸ 完成！"
echo "   $APP_BUNDLE"
echo "   $DMG_FINAL"
open -R "$DMG_FINAL" 2>/dev/null || true
