import Cocoa

final class StatusItem: NSObject, NSMenuDelegate {

    private let item: NSStatusItem
    private let onTrigger: () -> Void
    private let onOpenSettings: () -> Void
    private let onOpenAbout: () -> Void

    init(onTrigger: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onOpenAbout: @escaping () -> Void)
    {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onTrigger = onTrigger
        self.onOpenSettings = onOpenSettings
        self.onOpenAbout = onOpenAbout
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

        let capture = NSMenuItem(title: "Capture Now",
                                  action: #selector(triggerCapture),
                                  keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)

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

    @objc private func triggerCapture() { onTrigger() }
    @objc private func openSettings()   { onOpenSettings() }
    @objc private func openAbout()      { onOpenAbout() }
}
