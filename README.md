# CursorShot

CursorShot is a local macOS screenshot utility for capturing a window, crop, full screen, or annotated image from anywhere, then returning to the app where you started and pasting the right payload.

## Download

Download the latest `CursorShot.dmg` from the [releases page](https://github.com/ps-apps/CursorShot/releases/latest).

```sh
brew install --cask ps-apps/tap/cursorshot
```

Installed release builds check for updates automatically. You can also choose **Check for Updates...** from the CursorShot menu bar item.

## Permissions

CursorShot needs macOS permissions for:

- Screen Recording: capture windows, crops, and displays.
- Accessibility: return focus and paste into the app where you started.

For the most reliable macOS permissions flow, copy `CursorShot.app` to `/Applications` and open it from there. On first launch, CursorShot shows a setup window and opens the relevant System Settings panes when permissions are missing.

If macOS already shows CursorShot as enabled but the app still says permissions are missing, reset the stale TCC entries:

```sh
pkill -x CursorShot 2>/dev/null || true
tccutil reset Accessibility io.github.ps-apps.cursorshot
tccutil reset ScreenCapture io.github.ps-apps.cursorshot
```

Then reopen CursorShot and grant both permissions again. The Settings window also includes reset and privacy-pane buttons.

## Shortcuts

- Open Picker: Command Shift S by default, configurable in Settings.
- Cmd-Tab Quick: Command Shift 1 by default, configurable in Settings.
- Current-Space Quick: Command Shift 2 by default, configurable in Settings.

## Capture Overlay

Use the Open Picker shortcut or choose **Capture Now** from the menu bar when you want the picker workflow.

- **Window**: choose from detected visible app windows by number and name.
- **Crop**: drag a region to capture a cropped image.
- **Full Screen**: click a display to capture the full screen.
- **Annotate**: mark up the capture before it is pasted back.

Keyboard controls:

- Up/Down and Enter choose windows in the picker.
- Left/Right moves between Window, Crop, Full Screen, and Annotate controls.
- `W`, `C`, and `F` switch modes.
- `A` enables annotation before choosing a target.
- `Space` cycles modes.
- `Esc` cancels.

## Quick Capture

Use Current-Space Quick when the target window is visible on the same Space. Use Cmd-Tab Quick when the target is the next app in the Cmd-Tab rotation, even if that app is on another Space.

Both paths save the image, restore the original target, and paste the configured payload without opening the capture overlay.

## Annotation

Annotation mode supports arrows, rectangles, text labels, blur redaction, undo, redo, color, and stroke width. Press `Enter` in the editor to save the flattened PNG and paste it back. Press `Esc` to discard annotations and paste the original captured image.

## Privacy

CursorShot is local-first:

- Screenshots are saved locally.
- No telemetry is sent by CursorShot.
- Release builds contact GitHub only to check for app updates.
- Diagnostics are written to `~/Library/Logs/CursorShot/CursorShot.log` with sensitive identifying fields redacted.

Default screenshot storage is `~/Library/Application Support/CursorShot/Captures`, with a 7-day retention window.

## Build

```sh
swift build
swift test
```

## Run From Source

```sh
swift run CursorShot
```

## Package

```sh
chmod +x Scripts/package_app.sh
Scripts/package_app.sh
```

The package script creates `dist/CursorShot.dmg` for installs and `dist/updates/CursorShot-$APP_VERSION.zip` for automatic updates.

Maintainer release notes are in [docs/RELEASING.md](docs/RELEASING.md).

## License

CursorShot is released under the MIT License. See [LICENSE](LICENSE).
