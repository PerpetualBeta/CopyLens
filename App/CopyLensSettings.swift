import SwiftUI
import AppKit

/// App-specific settings rows for CopyLens. Slotted into
/// `JorvikSettingsView` via its `appSettings` ViewBuilder above the
/// shared "General" section, so the layout matches the rest of the
/// Jorvik suite (custom rows on top, JorvikKit's Launch-at-Login etc.
/// below).
struct CopyLensSettings: View {

    let onHotkeyChanged: (HotkeyConfig) -> Void

    @AppStorage("CopyLens.hudEnabled") private var hudEnabled: Bool = true

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
            // Vision is actually being asked to recognise — and, when
            // their system preference doesn't have an exact Vision
            // counterpart (e.g. en-GB → en-US), see the mapping.
            HStack {
                Text("OCR languages")
                Spacer()
                Text(OCRService.summarisedLanguages())
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
        }

        // Debug logging is a power-user knob, not for the Settings UI.
        // Enable with:
        //   defaults write cc.jorviksoftware.CopyLens CopyLens.debugLogging -bool YES
        // Then relaunch CopyLens. Output goes to /tmp/copylens.log.
    }
}
