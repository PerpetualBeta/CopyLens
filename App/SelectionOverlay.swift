import Cocoa

/// Borderless full-screen overlay used to draw a selection rectangle.
///
/// One `NSPanel` per `NSScreen` (all set to `.screenSaverWindow` level so
/// they appear above almost everything). The overlay dims the screen
/// slightly to signal "you're in selection mode"; the user clicks-and-drags
/// to define the rectangle. Escape cancels. Release commits.
///
/// The `onComplete` closure is fired exactly once with the drawn rect in
/// global Cocoa-coordinates (bottom-left origin, the same space NSScreen
/// reports). Cancellation passes `nil`.
final class SelectionOverlay {

    var onComplete: ((CGRect?) -> Void)?

    private var panels: [NSPanel] = []
    private var drawingScreen: NSScreen?

    func show() {
        dispatchPrecondition(condition: .onQueue(.main))
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.isMovableByWindowBackground = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

            let view = SelectionView(frame: screen.frame.atOrigin())
            view.onCommit = { [weak self] localRect in
                guard let self else { return }
                // Convert local (in this screen's space) → global Cocoa coords.
                let global = CGRect(x: localRect.origin.x + screen.frame.origin.x,
                                    y: localRect.origin.y + screen.frame.origin.y,
                                    width: localRect.width,
                                    height: localRect.height)
                self.finish(rect: global)
            }
            view.onCancel = { [weak self] in self?.finish(rect: nil) }
            panel.contentView = view
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }
        // The overlay panels are `.nonactivatingPanel`, so the app stays in
        // the background — and while CopyLens isn't the active app, macOS
        // keeps reasserting the frontmost app's arrow cursor over our overlay,
        // overriding anything we set. Activating CopyLens for the duration of
        // the selection lets our crosshair (cursorUpdate + the per-event
        // `set()` calls in SelectionView) actually take hold. Focus returns to
        // the previous app when the panels close in `finish()`.
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
    }

    private func finish(rect: CGRect?) {
        NSCursor.pop()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        let callback = onComplete
        onComplete = nil
        callback?(rect)
    }
}

// MARK: - Selection view

private final class SelectionView: NSView {

    var onCommit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var anchor: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // A single NSCursor.push() in SelectionOverlay.show() doesn't survive AppKit's
    // cursor-update cycle as the mouse moves over the panel — the system keeps
    // asking "what cursor here?" and reverts to the arrow. Answering via a
    // tracking area's cursorUpdate keeps the crosshair pinned the whole time.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // Belt-and-braces: cursorUpdate (above) is the documented hook, but on a
    // non-activating overlay panel the system's cursor-rect cycle doesn't
    // always honour it and reverts to the underlying app's arrow. Re-setting
    // the crosshair on every mouse event we receive — hover, press, drag —
    // pins it reliably regardless of which mechanism the OS is using.
    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.crosshair.set()
        anchor = convert(event.locationInWindow, from: nil)
        current = anchor
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let anchor, let current else { onCancel?(); return }
        let rect = NSRect(x: min(anchor.x, current.x),
                          y: min(anchor.y, current.y),
                          width: abs(anchor.x - current.x),
                          height: abs(anchor.y - current.y))
        // Reject degenerate rects (a click without drag).
        if rect.width < 4 || rect.height < 4 {
            onCancel?()
        } else {
            onCommit?(rect)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Subtle dim across the whole screen.
        NSColor(white: 0, alpha: 0.18).setFill()
        bounds.fill()

        // Punch out the selection rectangle so the underlying screen
        // shows through cleanly, then stroke its border.
        if let anchor, let current {
            let rect = NSRect(x: min(anchor.x, current.x),
                              y: min(anchor.y, current.y),
                              width: abs(anchor.x - current.x),
                              height: abs(anchor.y - current.y))

            NSColor.clear.setFill()
            rect.fill(using: .copy)

            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 1.5
            border.stroke()
        }
    }
}

private extension NSRect {
    /// Returns this rect with its origin moved to (0, 0) — useful when
    /// translating a screen's frame to the local content view's origin.
    func atOrigin() -> NSRect { NSRect(origin: .zero, size: size) }
}
