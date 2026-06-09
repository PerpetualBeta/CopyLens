import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: StatusItem?
    private var hotkey: HotkeyManager!
    private var capture: CaptureCoordinator!
    private var sparkleDelegate: SparkleDelegate?

    func applicationDidFinishLaunching(_ note: Notification) {
        clog("applicationDidFinishLaunching")

        capture = CaptureCoordinator()

        sparkleDelegate = SparkleDelegate()
        sparkleDelegate?.start()

        createStatusItem()

        // Add/remove the status-bar item when the user toggles its
        // visibility in Settings. Capture still works via the hotkey while
        // the icon is hidden; relaunching from /Applications brings it back.
        NotificationCenter.default.addObserver(
            forName: JorvikStatusItemVisibility.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyStatusItemVisibility()
        }

        hotkey = HotkeyManager()
        registerCaptureHotkey()
    }

    // MARK: - Status item lifecycle

    /// Build the menu-bar status item, honouring the user's "Show icon in
    /// menu bar" choice. When hidden, no item is created.
    private func createStatusItem() {
        guard JorvikStatusItemVisibility.isVisible else { return }
        statusItem = StatusItem(
            onTrigger:         { [weak self] in self?.beginCapture(source: "menu") },
            onOpenSettings:    { [weak self] in self?.openSettings() },
            onOpenAbout:       { Self.openAbout() },
            onCheckForUpdates: { [weak self] in self?.sparkleDelegate?.checkForUpdates() }
        )
    }

    /// Create or tear down the status-bar item to match the persisted
    /// visibility flag. Driven by the Settings toggle and by relaunch.
    private func applyStatusItemVisibility() {
        if JorvikStatusItemVisibility.isVisible {
            if statusItem == nil { createStatusItem() }
        } else if let item = statusItem {
            item.dispose()
            statusItem = nil
        }
    }

    /// Relaunching from /Applications is the user's way back to a hidden
    /// icon — restore visibility when the app is reopened.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        JorvikStatusItemVisibility.handleReopen()
        return true
    }

    // MARK: - Capture

    private func beginCapture(source: String) {
        clog("beginCapture source=\(source)")
        capture.start()
    }

    // MARK: - Hotkey lifecycle

    /// Loads the user's persisted hotkey config (or the seed default if
    /// none stored) and (re-)registers it. Called at launch and whenever
    /// the Settings recorder fires `onChange`.
    private func registerCaptureHotkey() {
        var cfg = HotkeyStore.read(HotkeyKeys.capture)
        if cfg.isEmpty {
            cfg = HotkeyConfig.defaultCapture
            // Persist the seed default so subsequent reads return it
            // directly (and the recorder displays "⌃⌥⇧⌘\" not "Click to set").
            HotkeyStore.write(HotkeyKeys.capture, cfg)
        }
        hotkey.register(cfg, slot: .capture) { [weak self] in
            self?.beginCapture(source: "hotkey")
        }
    }

    // MARK: - Settings & About windows

    private func openSettings() {
        JorvikSettingsView.showWindow(appName: "CopyLens") {
            CopyLensSettings(onHotkeyChanged: { [weak self] _ in
                self?.registerCaptureHotkey()
            })
        }
    }

    private static func openAbout() {
        JorvikAboutView.showWindow(appName: "CopyLens",
                                    repoName: "CopyLens",
                                    productPage: "copylens")
    }
}
