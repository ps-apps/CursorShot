# Releasing CursorShot

These notes are for maintainers. End users do not need to configure or understand the update framework; installed release builds check for updates automatically.

## Prerequisites

- GitHub release access for `ps-apps/CursorShot`.
- A Developer ID Application certificate for public distribution.
- A `notarytool` Keychain profile for Apple notarization.
- The Sparkle EdDSA private key in the maintainer Keychain under account `ed25519`, or a private-key file passed through `SPARKLE_ED_KEY_FILE`.

The production public EdDSA key is configured in `Scripts/package_app.sh`. Keep private keys and notarization credentials in Keychain or local ignored files only. Never commit them.

Store notarization credentials once with:

```sh
xcrun notarytool store-credentials CursorShot-notary
```

## Build Release Artifacts

```sh
APP_VERSION="0.4.3" \
APP_BUILD="17" \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="CursorShot-notary" \
Scripts/package_app.sh
```

The script creates:

- `dist/CursorShot.dmg`
- `dist/updates/CursorShot-$APP_VERSION.zip`

## Generate Appcast

```sh
APP_VERSION="0.4.3" \
RELEASE_TAG="v0.4.3" \
Scripts/generate_appcast.sh
```

`generate_appcast` keeps a cache of every archive it has seen, applies the
current `RELEASE_TAG` download-url-prefix to *all* of them, and emits binary
deltas between consecutive builds. After running it, hand-fix
`dist/updates/appcast.xml`:

- Restore each older version's `<enclosure url>` to its own tag (only the
  newest item belongs under the current `RELEASE_TAG`). The `edSignature` is
  over the file contents, so changing the URL does not invalidate it.
- Delete the `<sparkle:deltas>` block (we ship only full zips; otherwise the
  `.delta` files must be uploaded to the release too).

Then upload only the new `CursorShot-$APP_VERSION.zip`, the DMG, and `appcast.xml`.

The script signs the appcast using the private EdDSA key and writes:

- `dist/updates/appcast.xml`

## Publish

Upload these assets to the matching GitHub release:

- `dist/CursorShot.dmg`
- `dist/updates/CursorShot-$APP_VERSION.zip`
- `dist/updates/appcast.xml`

```sh
git tag v0.4.3
git push origin v0.4.3

gh release create v0.4.3 \
  dist/CursorShot.dmg \
  dist/updates/CursorShot-0.4.3.zip \
  dist/updates/appcast.xml \
  --title "CursorShot 0.4.3" \
  --notes "Signed and notarized CursorShot 0.4.3 release."
```

Release builds check this feed:

```text
https://github.com/ps-apps/CursorShot/releases/latest/download/appcast.xml
```

## Verification

Before publishing broadly:

```sh
swift test
codesign --verify --deep --strict --verbose=2 /path/to/CursorShot.app
spctl --assess --type execute --verbose=4 /path/to/CursorShot.app
```

`spctl` must accept the app for public distribution.
