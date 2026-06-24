#!/bin/bash
set -euo pipefail

PRODUCT="JapaneseLearningCard"
SRC="Sources/$PRODUCT"
BUILD_DIR=".build/app"
APP_BUNDLE="$BUILD_DIR/$PRODUCT.app"
STAGING="$BUILD_DIR/staging"
RESOURCES="$SRC/Resources"
ENTITLEMENTS="$SRC/$PRODUCT.entitlements"
DMG_NAME="$PRODUCT.dmg"
DMG_FINAL="$BUILD_DIR/$DMG_NAME"

echo "▸ 編譯 release binary..."
swift build -c release --product "$PRODUCT"

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

ENTITLEMENT_ARG=""
if [ -f "$ENTITLEMENTS" ]; then
    ENTITLEMENT_ARG="--entitlements $ENTITLEMENTS"
    echo "▸ 套用 entitlements: $ENTITLEMENTS"
else
    echo "⚠️ 找不到 $ENTITLEMENTS，iCloud 同步會被系統拒絕"
fi

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "▸ 使用 Developer ID 簽名 app: $SIGNING_IDENTITY"
    codesign --deep --force --options runtime --timestamp \
        $ENTITLEMENT_ARG \
        --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
else
    echo "▸ 用 ad-hoc 簽名 app..."
    codesign --force $ENTITLEMENT_ARG -s - "$APP_BUNDLE" 2>/dev/null || true
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
