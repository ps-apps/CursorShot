#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="cshot"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="${TMPDIR:-/tmp}/cshot-package"
APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR="$STAGING_DIR/.swiftpm-build"

cd "$ROOT_DIR"

rm -rf "$STAGING_DIR" "$DIST_DIR/$APP_NAME.app"
swift build -c release --scratch-path "$BUILD_DIR"
BUILD_BIN_DIR="$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
swift "$ROOT_DIR/Scripts/generate_icon.swift" "$RESOURCES_DIR/cshot.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>cshot</string>
  <key>CFBundleIdentifier</key>
  <string>com.local.cshot</string>
  <key>CFBundleName</key>
  <string>cshot</string>
  <key>CFBundleDisplayName</key>
  <string>cshot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>cshot</string>
  <key>CFBundleShortVersionString</key>
  <string>0.4.0</string>
  <key>CFBundleVersion</key>
  <string>14</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>cshot uses macOS automation permissions only to return focus and paste the captured screenshot reference into the app where you started.</string>
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
  codesign --force --sign - "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$DIST_DIR/$APP_NAME.dmg"
mkdir -p "$DIST_DIR"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DIST_DIR/$APP_NAME.dmg"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$DIST_DIR/$APP_NAME.dmg" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
  xcrun stapler staple "$DIST_DIR/$APP_NAME.dmg"
fi

echo "$APP_DIR"
echo "$DIST_DIR/$APP_NAME.dmg"
