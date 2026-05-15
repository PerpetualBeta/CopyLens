# CopyLens

Press **Hyper-\\** (Cmd+Ctrl+Opt+Shift+\\), draw a rectangle, get the contents on your clipboard. If there's text inside the rectangle, you get text. If there isn't, you get the cropped image. Same gesture, two outputs.

The motivating use case: copying a single column out of an HTML table in Mail — the boring solution involves copying the whole table and editing it back down. CopyLens makes "the column I'm looking at" the same gesture as "this whole table".

## How it works

1. **Hotkey** — `RegisterEventHotKey` registers Hyper-\\ as a global hotkey.
2. **Overlay** — borderless transparent `NSPanel`s span every screen at `.screenSaver` level; the user click-drags a selection rectangle. Escape cancels.
3. **Capture** — `SCScreenshotManager.captureImage` grabs that rectangle from the appropriate display at native pixel density.
4. **OCR** — `VNRecognizeTextRequest` at `.accurate` recognises text, returns observations sorted top-to-bottom, then left-to-right within rough "lines".
5. **Paste** — observations joined with newlines go on the pasteboard as a string. If Vision returned zero observations, the cropped image goes on the pasteboard as PNG+TIFF instead.
6. **HUD** — a brief bottom-centre toast reports which path ran ("Copied 247 chars" / "Copied image 320×180").

## Build

This is a Makefile project, same shape as Rainy Day and ActiveSpace.

```sh
make dev-build      # build + sign (Developer ID) the .app
make run            # build, kill any old instance, open the .app
make icon           # regenerate Resources/AppIcon.icns
```

The `dev-build` target expects:

- **Sparkle.framework** in the repo root. Copy it from a sibling Jorvik app (Rainy Day, ActiveSpace) — same version everywhere.
- **JorvikKit** sources in `App/JorvikKit/`. Stub files are in place so the build links; copy the real ones in from `/Users/jonathanhollin/Desktop/Jorvik Software/JorvikKit` when ready.
- **`../jorvik-release/release.mk`** for release targets (stamping, notarisation, appcast). Dev builds don't need it but the `include` line will fail without it — comment that line out for first compile if needed.

## Permissions

CopyLens needs **Screen Recording** permission. On first capture, macOS will prompt; grant it in System Settings → Privacy & Security → Screen Recording. No other entitlements are needed.

## Debug logging

```sh
defaults write cc.jorviksoftware.CopyLens CopyLens.debugLogging -bool YES
```

Then relaunch. Output goes to `/tmp/copylens.log`. Disable with `-bool NO` or `defaults delete`.

## Status

Starter skeleton — the full pipeline is wired up but unproven. Edge cases worth covering before first release:

- **Multi-display straddles.** Current code uses the midpoint of the drawn rect to pick a display; a selection that physically spans two screens captures only the half on the chosen display. Could be improved with a multi-`SCScreenshotManager` composite if it turns out to matter.
- **Retina precision.** Capture is in native pixels (×scale), but the rect width × scale is `Int`-truncated — the right-and-bottom edge may be one pixel short on fractional rects. Imperceptible for OCR.
- **Right-to-left text.** Vision handles RTL languages, but the sort heuristic (left → right within a line) reverses logical order for Arabic / Hebrew. Acceptable for the MVP English target.
- **Empty selection.** A click without drag is treated as cancel; selections smaller than 4×4 pt likewise. No HUD shown for cancels.
- **Hotkey conflicts.** Hyper-\\ is unusual enough to be safe, but a real hotkey recorder belongs in Settings before public release.
