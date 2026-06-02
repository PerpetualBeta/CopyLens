import Cocoa

final class StatusItem: NSObject, NSMenuDelegate {

    private let item: NSStatusItem
    private let onTrigger: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void
    private let onCheckForUpdates: () -> Void

    /// Held so `menuNeedsUpdate(_:)` can re-stamp the capture shortcut on
    /// every menu open — keeps the glyph in sync with whatever the user
    /// has configured in Settings without any cross-object coordination.
    private let captureItem: NSMenuItem

    init(onTrigger: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onOpenAbout: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void)
    {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onTrigger = onTrigger
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.onCheckForUpdates = onCheckForUpdates
        self.captureItem = NSMenuItem(title: "Capture Now",
                                       action: #selector(StatusItem.triggerCapture),
                                       keyEquivalent: "")
        super.init()

        applyIcon()

        // Redraw the status icon when the display configuration changes — the
        // menu bar's effective thickness can shrink (e.g. moving from a notched
        // display to an external one) and leave the pre-rendered glyph cropped.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyIcon()
        }

        let menu = NSMenu()
        menu.delegate = self

        // Standard Jorvik menu order — About first, then app-specific
        // actions, then Settings, then Quit. Matches Rainy Day,
        // BrowserCommander, etc.
        let about = NSMenuItem(title: "About CopyLens",
                                action: #selector(openAbout),
                                keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem.separator())

        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings…",
                                   action: #selector(openSettings),
                                   keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "Check for Updates…",
                                  action: #selector(checkForUpdates),
                                  keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit CopyLens",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        item.menu = menu
    }

    /// SF Symbol placeholder for the menu-bar glyph. The .app icon uses
    /// the bespoke generated artwork; this is just for the status item
    /// line and stays template-style so it adapts to light/dark menu bars.
    private func applyIcon() {
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "rectangle.dashed",
                                accessibilityDescription: "CopyLens")
        button.image?.isTemplate = true
    }

    // MARK: - NSMenuDelegate

    /// Refresh the capture-shortcut glyph just before the menu opens.
    /// Reads the live hotkey config from UserDefaults via HotkeyStore so
    /// changes made in Settings show up immediately — no observer
    /// plumbing required.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let cfg = HotkeyStore.read(HotkeyKeys.capture)
        if let (key, mods) = cfg.menuKeyEquivalent {
            captureItem.keyEquivalent = key
            captureItem.keyEquivalentModifierMask = mods
        } else {
            captureItem.keyEquivalent = ""
            captureItem.keyEquivalentModifierMask = []
        }
    }

    @objc private func triggerCapture()   { onTrigger() }
    @objc private func openSettings()     { onOpenSettings() }
    @objc private func openAbout()        { onOpenAbout() }
    @objc private func checkForUpdates()  { onCheckForUpdates() }
}
