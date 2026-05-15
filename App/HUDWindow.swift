import Cocoa

/// Brief feedback toast shown in the bottom-centre of the active screen
/// after a capture completes. Auto-dismisses after ~1.2 seconds.
///
/// Single-instance: a fresh `show()` cancels and replaces any in-flight
/// HUD so back-to-back captures don't queue toasts up.
enum HUDWindow {

    private static var current: NSPanel?
    private static var dismissWorkItem: DispatchWorkItem?

    static func show(text: String, subtext: String? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))

        // UserDefaults toggle from Settings. Default is true; explicit
        // false suppresses the HUD entirely. Read on every call so the
        // toggle in Settings takes effect without relaunch.
        if let v = UserDefaults.standard.object(forKey: "CopyLens.hudEnabled") as? Bool, v == false {
            return
        }

        dismissWorkItem?.cancel()
        current?.orderOut(nil)
        current = nil

        guard let screen = NSScreen.main else { return }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.alignment = .center

        let sub: NSTextField? = subtext.map { s in
            let f = NSTextField(labelWithString: s)
            f.font = .systemFont(ofSize: 12, weight: .regular)
            f.textColor = NSColor.white.withAlphaComponent(0.7)
            f.alignment = .center
            return f
        }

        let stack = NSStackView(views: [label] + (sub.map { [$0] } ?? []))
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 22, bottom: 14, right: 22)

        // Pill background via a wrapper view with a layer.
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(white: 0, alpha: 0.78).cgColor
        pill.layer?.cornerRadius = 14
        pill.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            stack.topAnchor.constraint(equalTo: pill.topAnchor),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
        ])

        // Size to content, then position bottom-centre of active screen.
        pill.layoutSubtreeIfNeeded()
        let fitted = stack.fittingSize
        let size = NSSize(width: fitted.width, height: fitted.height)
        let origin = NSPoint(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.minY + 120)

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = pill
        panel.orderFrontRegardless()

        current = panel

        let dismiss = DispatchWorkItem {
            current?.orderOut(nil)
            current = nil
            dismissWorkItem = nil
        }
        dismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: dismiss)
    }
}
