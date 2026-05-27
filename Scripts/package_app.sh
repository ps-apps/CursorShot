#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CursorShot"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-io.github.ps-apps.cursorshot}"
APP_VERSION="${APP_VERSION:-0.4.0}"
APP_BUILD="${APP_BUILD:-14}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-ps-apps/CursorShot}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/$GITHUB_REPOSITORY/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-ah7G3l8cfcR5wtu05KSG+64ClCBgdElJJjeLdpZ2Bw0=}"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="${TMPDIR:-/tmp}/CursorShot-package"
APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
BUILD_DIR="$STAGING_DIR/.swiftpm-build"
UPDATES_DIR="$DIST_DIR/updates"
DMG_ROOT="$STAGING_DIR/dmg-root"

sign_path() {
  local path="$1"
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$path"
  else
    codesign --force --sign - "$path"
  fi
}

notarize_file() {
  local path="$1"
  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    xcrun notarytool submit "$path" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --wait
  fi
}

cd "$ROOT_DIR"

rm -rf "$STAGING_DIR" "$DIST_DIR/$APP_NAME.app"
swift build -c release --scratch-path "$BUILD_DIR"
BUILD_BIN_DIR="$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$UPDATES_DIR"
cp "$BUILD_BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
ditto "$BUILD_BIN_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/Sparkle.framework"
swift "$ROOT_DIR/Scripts/generate_icon.swift" "$RESOURCES_DIR/CursorShot.icns"

SPARKLE_PUBLIC_KEY_PLIST=""
if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  SPARKLE_PUBLIC_KEY_PLIST="  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUVerifyUpdateBeforeExtraction</key>
  <true/>"
elif [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "SPARKLE_PUBLIC_ED_KEY is required for signed release builds." >&2
  exit 1
else
  echo "warning: SPARKLE_PUBLIC_ED_KEY is not set; update verification is not configured for this development build." >&2
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>CursorShot</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>CursorShot</string>
  <key>CFBundleDisplayName</key>
  <string>CursorShot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>CursorShot</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>CursorShot uses macOS automation permissions only to return focus and paste the captured screenshot reference into the app where you started.</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
  <key>SUAutomaticallyUpdate</key>
  <true/>
  <key>SUAllowsAutomaticUpdates</key>
  <true/>
$SPARKLE_PUBLIC_KEY_PLIST
</dict>
</plist>
PLIST

xattr -cr "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP_DIR" 2>/dev/null || true

sign_path "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Autoupdate"
sign_path "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/Updater.app"
sign_path "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
sign_path "$FRAMEWORKS_DIR/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
sign_path "$FRAMEWORKS_DIR/Sparkle.framework"
sign_path "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  NOTARY_ZIP="$STAGING_DIR/$APP_NAME-notary.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$NOTARY_ZIP"
  notarize_file "$NOTARY_ZIP"
  xcrun stapler staple "$APP_DIR"
fi

SPARKLE_ZIP="$UPDATES_DIR/$APP_NAME-$APP_VERSION.zip"
rm -f "$SPARKLE_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$SPARKLE_ZIP"

rm -f "$DIST_DIR/$APP_NAME.dmg"
mkdir -p "$DIST_DIR"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$APP_DIR" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DIST_DIR/$APP_NAME.dmg"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  notarize_file "$DIST_DIR/$APP_NAME.dmg"
  xcrun stapler staple "$DIST_DIR/$APP_NAME.dmg"
fi

echo "$APP_DIR"
echo "$DIST_DIR/$APP_NAME.dmg"
echo "$SPARKLE_ZIP"
