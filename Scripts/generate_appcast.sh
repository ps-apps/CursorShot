#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CursorShot"
APP_VERSION="${APP_VERSION:-0.4.1}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-ps-apps/CursorShot}"
RELEASE_TAG="${RELEASE_TAG:-v$APP_VERSION}"
UPDATES_DIR="${SPARKLE_UPDATES_DIR:-$ROOT_DIR/dist/updates}"
DOWNLOAD_URL_PREFIX="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG/}"
PRODUCT_URL="${PRODUCT_URL:-https://github.com/$GITHUB_REPOSITORY}"
GENERATE_APPCAST="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
SPARKLE_KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}"
SPARKLE_ED_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"

cd "$ROOT_DIR"

case "$DOWNLOAD_URL_PREFIX" in
  */) ;;
  *) DOWNLOAD_URL_PREFIX="$DOWNLOAD_URL_PREFIX/" ;;
esac

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  swift build -c release
fi

if [[ ! -d "$UPDATES_DIR" ]]; then
  echo "No update archive directory found at $UPDATES_DIR. Run Scripts/package_app.sh first." >&2
  exit 1
fi

SIGNING_ARGS=()
if [[ -n "$SPARKLE_ED_KEY_FILE" ]]; then
  SIGNING_ARGS+=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
elif [[ -n "$SPARKLE_KEYCHAIN_ACCOUNT" ]]; then
  SIGNING_ARGS+=(--account "$SPARKLE_KEYCHAIN_ACCOUNT")
fi

"$GENERATE_APPCAST" \
  "${SIGNING_ARGS[@]}" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "$PRODUCT_URL" \
  "$UPDATES_DIR"

echo "$UPDATES_DIR/appcast.xml"
echo "$UPDATES_DIR/$APP_NAME-$APP_VERSION.zip"
