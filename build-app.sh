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
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
SWIFT_FLAGS=""
if [ -n "$SIGNING_IDENTITY" ]; then
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

# 內嵌 Sparkle.framework (app 內自動更新)。
SPARKLE_FRAMEWORK="$BIN_PATH/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "▸ 內嵌 Sparkle.framework..."
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp -RP "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
    # SwiftPM 不會自動加「bundle 內找 framework」的 rpath，手工組 bundle 時
    # 必須補上 @executable_path/../Frameworks，否則 dyld 找不到 Sparkle 會直接 abort。
    # 在簽名前改 binary 才不會破壞簽章。
    if ! otool -l "$APP_BUNDLE/Contents/MacOS/$PRODUCT" | grep -q "@executable_path/../Frameworks"; then
        echo "▸ 補上 @executable_path/../Frameworks rpath..."
        install_name_tool -add_rpath "@executable_path/../Frameworks" \
            "$APP_BUNDLE/Contents/MacOS/$PRODUCT"
    fi
else
    echo "⚠️ 找不到 Sparkle.framework ($SPARKLE_FRAMEWORK)，自動更新將無法運作"
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

# 簽名 ID: Developer ID 或 ad-hoc ("-")。ad-hoc 不能 --timestamp。
if [ -n "$SIGNING_IDENTITY" ]; then
    SIGN_ID="$SIGNING_IDENTITY"
    TS_FLAG="--timestamp"
    echo "▸ 使用 Developer ID 簽名: $SIGN_ID"
else
    SIGN_ID="-"
    TS_FLAG=""
    echo "▸ 用 ad-hoc 簽名 (加 hardened runtime)..."
fi

# Sparkle 不能用 codesign --deep；nested 元件要由內往外個別簽。
# XPC services / helper 各自帶了自己的 entitlements，用 --preserve-metadata
# 保留，不要套 app 的 entitlements。
SPARKLE_V="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
if [ -d "$SPARKLE_V" ]; then
    echo "▸ 簽名 Sparkle 內嵌元件..."
    for comp in \
        "$SPARKLE_V/XPCServices/Downloader.xpc" \
        "$SPARKLE_V/XPCServices/Installer.xpc" \
        "$SPARKLE_V/Autoupdate" \
        "$SPARKLE_V/Updater.app"; do
        [ -e "$comp" ] || continue
        codesign --force --options runtime $TS_FLAG \
            --preserve-metadata=entitlements \
            --sign "$SIGN_ID" "$comp"
    done
    codesign --force --options runtime $TS_FLAG \
        --sign "$SIGN_ID" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
fi

echo "▸ 簽名 app (不使用 --deep)..."
# ad-hoc 簽名不能帶 restricted entitlements (AMFI 會直接 kill),
# 所以 ad-hoc entitlements 精簡版不含 iCloud。想跑 iCloud 同步要 Developer ID 版。
codesign --force --options runtime $TS_FLAG $ENTITLEMENT_ARG \
    --sign "$SIGN_ID" "$APP_BUNDLE"

if [ -z "$SIGNING_IDENTITY" ]; then
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
