# CopyLens

Hit your configurable shortcut, draw a rectangle anywhere on screen, get whatever's inside on your clipboard. If there's text in the rectangle you get text. If there isn't, you get the cropped image. Same gesture, two outputs — no mode switch, no second thought.

The motivating use case: copying one column out of an HTML table in an email. The boring solution is to copy the whole table, paste it somewhere, and trim it back to the column you wanted. CopyLens makes "this column I'm looking at" the same gesture as "this whole table" — you just draw a tighter box.

## Requirements

- macOS 14 (Sonoma) or later
- Universal binary (Apple Silicon and Intel)

## Installation

Two formats on every release — both signed and notarised, pick whichever suits:

- **[Installer (`.pkg`)](https://github.com/PerpetualBeta/CopyLens/releases/latest/download/CopyLens.pkg)** — recommended for first-time installs. Double-click to run; macOS Installer places `CopyLens.app` in `/Applications/` without quarantine or App Translocation.
- **[Download (`.zip`)](https://github.com/PerpetualBeta/CopyLens/releases/latest)** — unzip and drag `CopyLens.app` to your `/Applications/` folder.

After installation:

1. Launch CopyLens — a dashed-rectangle icon appears in the menu bar
2. Grant **Screen Recording** permission when prompted (CopyLens has to read pixels off your screen to OCR them; macOS prompts on first capture)

To uninstall: `pkill CopyLens` then drag `CopyLens.app` to the Trash.

## How it works

1. **Hit your shortcut.** A transparent overlay covers every connected display and the cursor switches to a crosshair.
2. **Drag a rectangle** around the content you want. Release to commit, Escape to cancel.
3. **CopyLens captures that rectangle** at native pixel density via ScreenCaptureKit and runs Apple's Vision framework over it.
4. **You get one of three outcomes:**
    - **A table** → if the text forms a grid, it's copied as both an HTML `<table>` and tab-separated values, so it pastes as real cells into Numbers, Excel, Sheets, Word, Pages and Mail — and as readable tab-separated columns into plain-text editors.
    - **Text found** → joined and placed on the clipboard as text, sorted top-to-bottom and left-to-right in reading order.
    - **No text found** → the cropped image is placed on the clipboard as PNG + TIFF, ready to paste into any app that accepts images.
5. A brief HUD confirms which path ran ("Copied table — 18 rows × 4 cols" / "Copied 247 chars" / "Copied image 320×180"). All can be paste-targeted immediately.

Because the gesture is the same regardless of content, you don't have to decide ahead of time whether you want text or an image. Draw the box; CopyLens does the right thing.

### One column from a table

Draw a tight rectangle that covers just one column's width. Vision only sees text inside the rectangle, so the result is exactly that column — top to bottom, one line per row, plain text. Paste anywhere. Tables in Mail, in browser pages, in PDFs, in screenshots-of-PDFs — all the same gesture.

### A whole table

Draw a rectangle around a multi-column table — a dealer ledger, a spreadsheet region, a table in a PDF or web page. CopyLens reconstructs the grid geometrically (clustering recognised words into rows by their vertical position and into columns by the whitespace corridors between them) and copies it in two forms at once: an HTML table and tab-separated values. Paste into a spreadsheet and it lands as cells; paste into Word or Mail and it's a formatted table; paste into a code editor and you get clean tab-separated columns. Detection is automatic and conservative — if the region isn't convincingly tabular, CopyLens falls back to plain text.

### A region of a diagram

Draw a rectangle around a chart, a panel of an image, a UI mockup. Vision finds no text (or filters out as noise anything it does), so CopyLens drops the cropped image on the clipboard instead. Paste into Notes, into a message, into a Keynote slide.

## Settings

Click the menu bar icon → **Settings…**:

- **Hotkey** — click the field and press the combination you want. Default is **⌃⌥⇧⌘\\** (Hyper-\\); change it to anything that includes at least one modifier.
- **Show feedback HUD** — toggle the toast that appears after each capture. Off if you'd rather work silently.
- **OCR languages** — read-only display. CopyLens picks recognition languages from your system's preferred language list, intersected with Vision's supported set, with English always appended as a fallback. If your Mac is set to French, you'll see `fr-FR, en-US` here and both will be recognised on every capture.
- **Show icon in menu bar** — hide the menu-bar icon while CopyLens keeps running. The app remains reachable via its keyboard shortcut; your choice persists across launches, including login auto-start. *Shown only on macOS 14–15 — on macOS 26 (Tahoe) and later, use System Settings → Menu Bar, which provides this natively.*
- **Launch at Login** — start automatically when you log in.

All settings persist immediately, no Save/OK button.

If you've hidden the menu-bar icon and want it back, simply re-open CopyLens from your Applications folder — it reappears immediately.

## Auto-update

CopyLens uses [Sparkle 2.x](https://sparkle-project.org/) for auto-update. Updates check daily against `https://jorviksoftware.cc/appcasts/copylens.xml`. Trigger a manual check from the menu bar → **Check for Updates…**.

Updates are EdDSA-signed; your copy will only install genuine Jorvik Software releases.

## Privacy

- **No telemetry.** No usage reporting, no log file unless you explicitly turn one on (`defaults write cc.jorviksoftware.CopyLens CopyLens.debugLogging -bool YES` writes lifecycle lines to `/tmp/copylens.log`; off by default), no network requests beyond Sparkle's appcast fetch.
- **No camera, microphone, network access.** Captures stay on-device — Vision OCR runs locally; pasteboard writes are local.
- **Permissions:** Screen Recording is the only permission CopyLens requests. Accessibility is **not** required (the hotkey uses Carbon's `RegisterEventHotKey`, which doesn't need AX).

## Multi-display

The overlay covers every connected screen at once; you can drag your rectangle starting on whichever screen you're working on. The capture is taken from the screen containing the rectangle's midpoint, so a rectangle that physically straddles two screens captures from the screen it's mostly on (a deliberate simplification — straddling captures are rare enough not to warrant the per-display composition cost).

## Architecture

| File | Purpose |
|------|---------|
| `AppDelegate.swift` | Lifecycle, hotkey registration, Settings/About wire-up |
| `StatusItem.swift` | Menu bar icon, menu items, click routing |
| `HotkeyManager.swift` | Carbon `RegisterEventHotKey` wrapper, slot/config-driven so the recorder can re-register on the fly |
| `HotkeyRecorder.swift` | SwiftUI recorder field, `HotkeyConfig` value type, `HotkeyStore` UserDefaults persistence, glyph formatter |
| `CaptureCoordinator.swift` | End-to-end pipeline orchestration |
| `SelectionOverlay.swift` | Transparent per-screen panels, rect-drag drawing |
| `Screenshot.swift` | ScreenCaptureKit capture, Cocoa→CG coord flip, native pixel density |
| `OCRService.swift` | Vision text recognition, reading-order sort, word-level boxes, locale-driven language picker |
| `TableDetector.swift` | Geometric grid reconstruction (X-Y cut) from positioned words |
| `Pasteboard.swift` | Text, image, or table (HTML + TSV) clipboard writer |
| `HUDWindow.swift` | Bottom-centre feedback toast, UserDefaults-gated |
| `CopyLensSettings.swift` | SwiftUI app-specific settings rows, slotted into JorvikSettingsView |
| `SparkleDelegate.swift` | Sparkle 2.x bootstrap |
| `Log.swift` | Optional debug logging behind a UserDefaults flag |
| `JorvikKit/*` | Vendored shared components — About modal, Settings frame, update checker, window helper |

## Building from source

CopyLens builds via the shared Jorvik `release.mk`. With the `jorvik-release` sibling repo cloned alongside it and [GNU Make](https://formulae.brew.sh/formula/make) 4 installed:

- Clone the repo: `git clone https://github.com/PerpetualBeta/CopyLens.git`
- Local install (signed with the Jorvik Developer ID): `gmake dev-build`
- Run the freshly-built copy: `gmake run`
- Signed, notarised, stapled `.zip` + `.pkg` ready to ship: `gmake release`

## Attribution

CopyLens uses [Sparkle 2.x](https://sparkle-project.org/) for auto-update (MIT). Text recognition and screen capture are provided by Apple's Vision and ScreenCaptureKit frameworks — part of macOS, no separate attribution required.

See [`ATTRIBUTIONS.md`](ATTRIBUTIONS.md) for full Sparkle licence text.

## Quitting

Click the menu-bar icon and choose **Quit CopyLens**. If you've hidden that icon, re-open CopyLens from your Applications folder first to bring it back, then quit from the menu.

---

CopyLens is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
