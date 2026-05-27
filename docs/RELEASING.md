# Releasing CursorShot

These notes are for maintainers. End users do not need to configure or understand the update framework; installed release builds check for updates automatically.

## Prerequisites

- GitHub release access for `ps-apps/CursorShot`.
- A Developer ID Application certificate for public distribution.
- Apple notarization credentials:
  - `APPLE_ID`
  - `APPLE_TEAM_ID`
  - `APPLE_APP_PASSWORD`
- The Sparkle EdDSA private key in the maintainer Keychain under account `ed25519`, or a private-key file passed through `SPARKLE_ED_KEY_FILE`.

The production public EdDSA key is configured in `Scripts/package_app.sh`. Keep the private key secure and never commit it.

## Build Release Artifacts

```sh
APP_VERSION="0.4.1" \
APP_BUILD="15" \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
Scripts/package_app.sh
```

The script creates:

- `dist/CursorShot.dmg`
- `dist/updates/CursorShot-$APP_VERSION.zip`

## Generate Appcast

```sh
APP_VERSION="0.4.1" \
RELEASE_TAG="v0.4.1" \
Scripts/generate_appcast.sh
```

The script signs the appcast using the private EdDSA key and writes:

- `dist/updates/appcast.xml`

## Publish

Upload these assets to the matching GitHub release:

- `dist/CursorShot.dmg`
- `dist/updates/CursorShot-$APP_VERSION.zip`
- `dist/updates/appcast.xml`

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
