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
APP_VERSION="0.4.2" \
APP_BUILD="16" \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARYTOOL_PROFILE="CursorShot-notary" \
Scripts/package_app.sh
```

The script creates:

- `dist/CursorShot.dmg`
- `dist/updates/CursorShot-$APP_VERSION.zip`

## Generate Appcast

Remove older version zips from `dist/updates/` first, leaving only the new
`CursorShot-$APP_VERSION.zip`. `generate_appcast` rewrites the download URL of
every zip still present to the current `RELEASE_TAG`, which would point old
versions at the wrong release (and emit unwanted binary deltas).

```sh
rm -f dist/updates/CursorShot-*.zip.bak  # keep only the new version's zip
APP_VERSION="0.4.2" \
RELEASE_TAG="v0.4.2" \
Scripts/generate_appcast.sh
```

The script signs the appcast using the private EdDSA key and writes:

- `dist/updates/appcast.xml`

## Publish

Upload these assets to the matching GitHub release:

- `dist/CursorShot.dmg`
- `dist/updates/CursorShot-$APP_VERSION.zip`
- `dist/updates/appcast.xml`

```sh
git tag v0.4.2
git push origin v0.4.2

gh release create v0.4.2 \
  dist/CursorShot.dmg \
  dist/updates/CursorShot-0.4.2.zip \
  dist/updates/appcast.xml \
  --title "CursorShot 0.4.2" \
  --notes "Signed and notarized CursorShot 0.4.2 release."
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
