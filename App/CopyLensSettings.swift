import SwiftUI
import AppKit
import CoreGraphics

/// App-specific settings rows for CopyLens. Slotted into
/// `JorvikSettingsView` via its `appSettings` ViewBuilder above the
/// shared "General" section, so the layout matches the rest of the
/// Jorvik suite (Permissions → app-specific → General).
struct CopyLensSettings: View {

    let onHotkeyChanged: (HotkeyConfig) -> Void

    @AppStorage("CopyLens.hudEnabled") private var hudEnabled: Bool = true

    /// CGPreflightScreenCaptureAccess flips immediately when the user
    /// grants Screen Recording in System Settings, but SwiftUI doesn't
    /// see the change without a redraw trigger. Re-poll on appear so
    /// returning to the Settings window after granting refreshes the
    /// indicator without a relaunch.
    @State private var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()

    var body: some View {
        Section("Permissions") {
            HStack {
                Text("Screen Recording")
                Spacer()
                if screenRecordingGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Grant Access") {
                        // First call surfaces the system TCC prompt; after
                        // a prior denial CG silently records a request and
                        // returns false, so also nudge the user toward
                        // the Settings pane where they'd actually flip it.
                        _ = CGRequestScreenCaptureAccess()
                        screenRecordingGranted = CGPreflightScreenCaptureAccess()
                        if !screenRecordingGranted {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .font(.caption)
                }
            }
            Text("Screen Recording is required to capture the rectangle you draw so CopyLens can read text from it (or copy the cropped image when there's no text).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        MenuBarVisibilitySettings()

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
        .onAppear {
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        }

        // Debug logging is a power-user knob, not for the Settings UI.
        // Enable with:
        //   defaults write cc.jorviksoftware.CopyLens CopyLens.debugLogging -bool YES
        // Then relaunch CopyLens. Output goes to /tmp/copylens.log.
    }
}
