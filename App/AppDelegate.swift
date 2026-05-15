import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: StatusItem!
    private var hotkey: HotkeyManager!
    private var capture: CaptureCoordinator!
    private var sparkleDelegate: SparkleDelegate?
    private var updateChecker: JorvikUpdateChecker!

    func applicationDidFinishLaunching(_ note: Notification) {
        clog("applicationDidFinishLaunching")

        capture = CaptureCoordinator()
        updateChecker = JorvikUpdateChecker(repoName: "CopyLens")

        statusItem = StatusItem(
            onTrigger:      { [weak self] in self?.beginCapture(source: "menu") },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenAbout:    { Self.openAbout() }
        )

        hotkey = HotkeyManager()
        registerCaptureHotkey()

        sparkleDelegate = SparkleDelegate()
        sparkleDelegate?.start()
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
        JorvikSettingsView.showWindow(
            appName: "CopyLens",
            updateChecker: updateChecker
        ) {
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
