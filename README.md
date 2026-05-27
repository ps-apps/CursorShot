# CursorShot

CursorShot is a local macOS productivity utility for capturing a screenshot from anywhere, saving it to disk, returning to the original cursor location, and pasting the right reference for the target app.

## Build

```sh
swift build
swift test
```

## Run

```sh
swift run CursorShot
```

The app appears as a menu bar item. Grant Screen Recording and Accessibility permissions when prompted.

For the most reliable macOS permissions flow, copy `CursorShot.app` to `/Applications` and open it from there. On first launch, CursorShot shows a setup window and opens the relevant System Settings panes when permissions are missing.

If macOS already shows CursorShot as enabled but the app still says permissions are missing, reset the stale TCC entries:

```sh
pkill -x CursorShot 2>/dev/null || true
tccutil reset Accessibility com.local.CursorShot
tccutil reset ScreenCapture com.local.CursorShot
```

Then reopen CursorShot and grant both permissions again. The Settings window also includes reset and privacy-pane buttons.

## Package

```sh
chmod +x Scripts/package_app.sh
Scripts/package_app.sh
```

For Developer ID signing:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" Scripts/package_app.sh
```

For notarization, provide App Store Connect credentials as environment variables:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
Scripts/package_app.sh
```

The package script creates `dist/CursorShot.dmg`. The raw staged app is signed and verified during packaging, then bundled into the DMG.

## Defaults

- Open Picker shortcut: Command Shift S by default, configurable in Settings.
- Current-Space Quick shortcut: Command Shift 2 by default, configurable in Settings.
- Cmd-Tab Quick shortcut: Command Shift 1 by default, configurable in Settings.
- Storage: `~/Library/Application Support/CursorShot/Captures`
- Retention: 7 days
- Injection: smart by app
- Diagnostics: `~/Library/Logs/CursorShot/CursorShot.log`

## Immediate Capture

Use the Current-Space Quick shortcut when the target window is visible on the same Space. Use the Cmd-Tab Quick shortcut when the target is the next app in the Cmd-Tab rotation, even if that app is on another Space. Both paths save the image, restore the original target, and paste the configured payload without opening the capture overlay.

## Capture Overlay

Use the Open Picker shortcut or open **Capture Now** from the menu bar when you want the picker workflow.

- **Window**: default mode. Use the sidebar to see every detected visible app window by number and name. Click a row, click a highlighted window, press its number, or use Up/Down and Enter to capture it.
- **Crop**: drag a region to capture a cropped image.
- **Full**: click a display to capture the full screen.
- Press Left/Right to move between Window, Crop, Full Screen, and Annotate controls.
- Press `W`, `C`, or `F` to switch to Window, Crop, or Full Screen mode.
- Press `A` before choosing a window, crop, or full screen capture to open the annotation editor.
- Press `Space` to cycle modes or `Esc` to cancel. Other keys and mouse clicks are swallowed while the overlay is open.
- Smart injection copies image data for non-terminal apps and terminal-safe path text for terminal apps.
- CursorShot animates the captured payload back toward the original cursor position, pastes into the originating app when possible, and leaves the generated payload on the system clipboard so it can be pasted again.

## Annotation

Annotation mode is local-only. It supports arrows, rectangles, text labels, blur redaction, undo, redo, color, and stroke width. Press `Enter` in the editor to save the flattened PNG and paste it back. Press `Esc` to discard annotations and paste the original captured image.
