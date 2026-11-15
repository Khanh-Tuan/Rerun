# Rerun

A one-tap arcade game: drive laps around a ring while every lap you finish comes back the other way as a ghost. Tap to switch lanes, grab stars, don't hit yourself.

The game itself is a single HTML/JavaScript file. The iOS app is a small Swift wrapper that shows that file full-screen, with everything bundled inside the app.

## What's in this repository

| Path | What it is |
|---|---|
| `src/rerun.html` | **The game.** Edit this file to change the game. |
| `web/index.html` | Standalone page built from `src/rerun.html`. The iOS app loads this one. Don't edit it by hand. |
| `ios/` | The iOS app: Swift source, app icon, and `project.yml` (turned into an Xcode project with XcodeGen). |
| `tools/build-web.ps1` | Rebuilds `web/index.html` from `src/rerun.html`. |
| `tools/make-icon.ps1` | Redraws the 1024×1024 app icon (Windows only). |
| `docs/github-upload.md` | How to put this project on GitHub without installing anything. |
| `docs/ios-submit-guide.md` | Step-by-step guide for building on a Mac and submitting to the App Store. |
| `docs/privacy-policy.md` | Privacy policy text to publish (Apple requires a privacy policy URL). |

## Changing the game

1. Edit `src/rerun.html`.
2. Rebuild the app page (Windows):
   ```
   powershell -ExecutionPolicy Bypass -File tools\build-web.ps1
   ```
   On a Mac with PowerShell installed: `pwsh tools/build-web.ps1`.
3. Commit both `src/rerun.html` and `web/index.html`.

You can also open `web/index.html` directly in a browser to play it.

## Tuning

Gameplay numbers (lap speed, ghost speed, hitbox, grace period) are in the "Tuning knobs" block at the top of the script in `src/rerun.html`. Skin names and prices are in the `SKINS` list.

## Fonts

The game uses four fonts from Google Fonts, all under the SIL Open Font License (free for commercial use, including inside an app): Monoton, Pixelify Sans, Silkscreen and VT323. They are bundled in `web/fonts/` next to their licence texts (`OFL-*.txt`), so the game makes no network requests and works offline. Keep the licence files with the fonts whenever you ship them.

The font paths are relative to `web/`, so open `web/index.html` to play locally; opening `src/rerun.html` directly shows fallback fonts.

## Before publishing

See the open items from the IP check: pick a final name (the name "Rerun" is crowded) and run trademark and store searches on it.
