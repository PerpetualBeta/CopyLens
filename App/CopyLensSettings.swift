import SwiftUI
import AppKit

/// App-specific settings rows for CopyLens. Slotted into
/// `JorvikSettingsView` via its `appSettings` ViewBuilder above the
/// shared "General" section, so the layout matches the rest of the
/// Jorvik suite (custom rows on top, JorvikKit's Launch-at-Login etc.
/// below).
struct CopyLensSettings: View {

    let onHotkeyChanged: (HotkeyConfig) -> Void

    @AppStorage("CopyLens.hudEnabled")     private var hudEnabled: Bool = true
    @AppStorage("CopyLens.debugLogging")   private var debugLogging: Bool = false

    var body: some View {
        Section("Capture") {
            HStack {
                Text("Hotkey")
                Spacer()
                HotkeyRecorderView(storageKey: HotkeyKeys.capture,
                                    onChange: onHotkeyChanged)
                    .frame(width: 180, height: 24)
            }
        }

        Section("Behaviour") {
            Toggle("Show feedback HUD", isOn: $hudEnabled)
            // OCR languages are derived from the system locale (with
            // English as a fallback); not user-editable here. Surface
            // the computed list so the user can sanity-check what
            // Vision is actually being asked to recognise.
            HStack {
                Text("OCR languages")
                Spacer()
                Text(OCRService.summarisedLanguages())
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        }

        Section("Diagnostics") {
            Toggle("Write debug log to /tmp/copylens.log", isOn: $debugLogging)
            // Debug logging is read once at process start (the file
            // handle is opened or not depending on the flag), so
            // toggling at runtime needs a relaunch to take effect.
            // Flag this so the user isn't surprised by the lag.
            Text("Takes effect after the next CopyLens launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
