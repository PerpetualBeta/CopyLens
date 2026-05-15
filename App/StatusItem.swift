import Cocoa

final class StatusItem: NSObject, NSMenuDelegate {

    private let item: NSStatusItem
    private let onTrigger: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void

    /// Held so `menuNeedsUpdate(_:)` can re-stamp the capture shortcut on
    /// every menu open — keeps the glyph in sync with whatever the user
    /// has configured in Settings without any cross-object coordination.
    private let captureItem: NSMenuItem

    init(onTrigger: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onOpenAbout: @escaping () -> Void)
    {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onTrigger = onTrigger
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
        self.captureItem = NSMenuItem(title: "Capture Now",
                                       action: #selector(StatusItem.triggerCapture),
                                       keyEquivalent: "")
        super.init()

        if let button = item.button {
            // SF Symbol placeholder for the menu-bar glyph. The .app icon
            // uses the bespoke generated artwork; this is just for the
            // status item line and stays template-style so it adapts to
            // light/dark menu bars.
            button.image = NSImage(systemSymbolName: "rectangle.dashed",
                                    accessibilityDescription: "CopyLens")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self

        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings…",
                                   action: #selector(openSettings),
                                   keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: "About CopyLens",
                                action: #selector(openAbout),
                                keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit CopyLens",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        item.menu = menu
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

    @objc private func triggerCapture() { onTrigger() }
    @objc private func openSettings()   { onOpenSettings() }
    @objc private func openAbout()      { onOpenAbout() }
}
