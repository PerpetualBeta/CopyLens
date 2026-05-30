import Cocoa
import ScreenCaptureKit

/// Captures a rectangular region of the screen via ScreenCaptureKit.
///
/// Input rect is in **global Cocoa coordinates** (the space NSScreen reports
/// — bottom-left origin, y-up). ScreenCaptureKit wants display-local CG
/// coordinates (top-left origin, y-down), so we flip + translate per-display.
///
/// Returns the captured CGImage at native pixel density together with the
/// source display's `backingScaleFactor` (2.0 on Retina/5K, 1.0 on a
/// sub-Retina display), or nil if the rect doesn't intersect any display,
/// the user hasn't granted Screen Recording permission, or the capture
/// itself fails. Errors are logged.
///
/// The scale travels with the image so the OCR path can decide whether to
/// enhance a low-DPI capture before recognition — see `OCRService`. We pass
/// the real `backingScaleFactor` rather than recomputing pixels ÷ points at
/// the call site, because integer rounding of the SCK output dimensions can
/// nudge that ratio just under 2.0 and misclassify a genuine Retina capture.
enum Screenshot {

    static func capture(globalRect cocoaRect: CGRect) async -> (image: CGImage, scale: CGFloat)? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                onScreenWindowsOnly: true)

            // Find which NSScreen the rect lives on. Multi-screen support:
            // we use the screen whose frame contains the rect's midpoint —
            // simpler than supporting a single drag straddling two screens
            // (and you can't physically straddle without weird mouse paths).
            let midpoint = CGPoint(x: cocoaRect.midX, y: cocoaRect.midY)
            guard let nsScreen = NSScreen.screens.first(where: { $0.frame.contains(midpoint) }) else {
                clog("Screenshot: rect midpoint not on any screen — \(midpoint)")
                return nil
            }

            // Match NSScreen → SCDisplay by CGDirectDisplayID.
            let cgID = (nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            guard let display = content.displays.first(where: { $0.displayID == cgID }) else {
                clog("Screenshot: no SCDisplay for CGDirectDisplayID=\(cgID)")
                return nil
            }

            // Convert global Cocoa rect → display-local CG rect.
            //   Cocoa: origin bottom-left of NSScreen.frame; y-up
            //   CG:    origin top-left of display.frame;     y-down
            let screenFrame = nsScreen.frame
            let localX = cocoaRect.origin.x - screenFrame.origin.x
            let localCocoaY = cocoaRect.origin.y - screenFrame.origin.y
            let localCGY = screenFrame.height - localCocoaY - cocoaRect.height
            let sourceRect = CGRect(x: localX, y: localCGY,
                                    width: cocoaRect.width,
                                    height: cocoaRect.height)

            let config = SCStreamConfiguration()
            config.sourceRect = sourceRect
            let scale = nsScreen.backingScaleFactor
            config.width = Int(cocoaRect.width * scale)
            config.height = Int(cocoaRect.height * scale)
            config.scalesToFit = false
            config.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                    configuration: config)
            return (image, scale)
        } catch {
            clog("Screenshot: capture failed — \(error)")
            return nil
        }
    }
}
