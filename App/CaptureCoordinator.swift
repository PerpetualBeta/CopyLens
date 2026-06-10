import Cocoa

/// Owns the end-to-end capture flow:
///   1. Show the selection overlay across all screens.
///   2. Receive the drawn rect (or `nil` if the user pressed Escape).
///   3. Take a screenshot of that rect via ScreenCaptureKit.
///   4. Run Vision OCR on the screenshot.
///   5. Write text to the pasteboard if any was found; otherwise write
///      the cropped image. Show a HUD reporting which path ran.
///
/// Re-entrancy is guarded: pressing the hotkey while a capture is in
/// flight is a no-op until the previous flow completes.
final class CaptureCoordinator {

    private var overlay: SelectionOverlay?
    private var inFlight = false

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !inFlight else {
            clog("CaptureCoordinator: ignoring re-entrant start — capture already in flight")
            return
        }
        inFlight = true

        let overlay = SelectionOverlay()
        self.overlay = overlay
        overlay.onComplete = { [weak self] rect in
            guard let self else { return }
            self.overlay = nil
            if let rect {
                Task { @MainActor in
                    await self.runPipeline(globalRect: rect)
                    self.inFlight = false
                }
            } else {
                clog("CaptureCoordinator: cancelled")
                self.inFlight = false
            }
        }
        overlay.show()
    }

    @MainActor
    private func runPipeline(globalRect: CGRect) async {
        clog("CaptureCoordinator: capturing rect=\(globalRect)")

        guard let capture = await Screenshot.capture(globalRect: globalRect) else {
            clog("CaptureCoordinator: screenshot failed")
            HUDWindow.show(text: "Capture failed", subtext: "Check Screen Recording permission")
            return
        }
        let image = capture.image

        // OCR reads from an enhanced copy on low-DPI captures; the native
        // `image` below is what gets pasted when no text is found.
        let result = await OCRService.recognize(image, sourceScale: capture.scale)
        if result.isEmpty {
            clog("CaptureCoordinator: no text recognised — copying image (\(image.width)x\(image.height))")
            Pasteboard.copy(image: image)
            HUDWindow.show(text: "Copied image",
                           subtext: "\(image.width)×\(image.height) px")
        } else if let table = TableDetector.detect(result.words) {
            clog("CaptureCoordinator: table detected \(table.rowCount)×\(table.columnCount) — copying as table")
            Pasteboard.copy(table: table)
            HUDWindow.show(text: "Copied table",
                           subtext: "\(table.rowCount) row\(table.rowCount == 1 ? "" : "s") × \(table.columnCount) col\(table.columnCount == 1 ? "" : "s")")
        } else {
            let joined = result.lines.joined(separator: "\n")
            clog("CaptureCoordinator: \(result.lines.count) line(s), \(joined.count) chars — copying text")
            Pasteboard.copy(text: joined)
            HUDWindow.show(text: "Copied \(joined.count) chars",
                           subtext: "\(result.lines.count) line\(result.lines.count == 1 ? "" : "s")")
        }
    }
}
