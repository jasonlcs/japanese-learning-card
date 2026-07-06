#!/usr/bin/env bash
#
# build-ios-app.sh — assemble and run the iOS app on a Simulator.
#
# A SwiftPM `executableTarget` builds an iOS Mach-O binary but never wraps it in
# an installable `.app` bundle (no Info.plist / bundle id), so the Simulator has
# nothing to launch. This script mirrors `build-app.sh` (which hand-assembles the
# macOS `.app`): it builds the simulator executable, wraps it in a `.app` with a
# generated Info.plist, then installs and launches it on a Simulator.
#
# Usage:
#   ./build-ios-app.sh                 # build + install + launch on a simulator
#   SIM_NAME="iPhone 16 Pro" ./build-ios-app.sh
#   ./build-ios-app.sh --build-only    # assemble the .app, don't install/launch

set -euo pipefail

cd "$(dirname "$0")"

SCHEME="JapaneseLearningCardIOS"
EXECUTABLE="JapaneseLearningCardIOS"
BUNDLE_ID="io.github.jasonlcs.japaneselearningcard"
DISPLAY_NAME="日語學習卡"
SHORT_VERSION="0.2.38"
BUNDLE_VERSION="2038"
DEPLOYMENT_TARGET="17.0"
SIM_NAME="${SIM_NAME:-iPhone 16}"

BUILD_ONLY=false
[[ "${1:-}" == "--build-only" ]] && BUILD_ONLY=true

DERIVED="$PWD/.build-ios"
APP_DIR="$DERIVED/$EXECUTABLE.app"

echo "==> Building $SCHEME for the iOS Simulator…"
xcodebuild \
    -scheme "$SCHEME" \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$DERIVED/DerivedData" \
    -configuration Debug \
    build \
    | grep -E "error:|warning:|BUILD" || true

PRODUCTS="$DERIVED/DerivedData/Build/Products/Debug-iphonesimulator"
BIN="$PRODUCTS/$EXECUTABLE"
if [[ ! -x "$BIN" ]]; then
    echo "error: built executable not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling $APP_DIR…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
cp "$BIN" "$APP_DIR/$EXECUTABLE"

# Copy any resource bundles SwiftPM produced (e.g. *_*.bundle) next to the binary.
for b in "$PRODUCTS"/*.bundle; do
    [[ -e "$b" ]] && cp -R "$b" "$APP_DIR/" || true
done

cat > "$APP_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>JapaneseLearningCard</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key><string>$BUNDLE_VERSION</string>
    <key>LSRequiresIPhoneOS</key><true/>
    <key>MinimumOSVersion</key><string>$DEPLOYMENT_TARGET</string>
    <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
    <key>UILaunchScreen</key><dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
    <key>DTPlatformName</key><string>iphonesimulator</string>
</dict>
</plist>
PLIST

echo "==> Built $APP_DIR"
$BUILD_ONLY && { echo "(--build-only: skipping install/launch)"; exit 0; }

# Pick a booted simulator if there is one, else boot the requested device.
UDID="$(xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json,sys;d=json.load(sys.stdin)["devices"];print(next((x["udid"] for v in d.values() for x in v if x["state"]=="Booted"),""))')"
if [[ -z "$UDID" ]]; then
    UDID="$(xcrun simctl list devices available -j | /usr/bin/python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next((x['udid'] for v in d.values() for x in v if x['name']=='$SIM_NAME'),''))")"
    [[ -z "$UDID" ]] && { echo "error: no simulator named '$SIM_NAME'" >&2; exit 1; }
    echo "==> Booting $SIM_NAME ($UDID)…"
    xcrun simctl boot "$UDID"
fi
open -a Simulator --args -CurrentDeviceUDID "$UDID" || open -a Simulator

echo "==> Installing onto $UDID…"
xcrun simctl install "$UDID" "$APP_DIR"
echo "==> Launching $BUNDLE_ID…"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
echo "==> Done."
