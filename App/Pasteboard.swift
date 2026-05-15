import Cocoa

/// Writes either text or an image to the general pasteboard.
///
/// Each call replaces previous pasteboard contents — the standard Cocoa
/// idiom (clear → declare types → set data) rather than appending to a
/// pasteboard item, so paste-target apps see exactly one representation.
enum Pasteboard {

    static func copy(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString(text, forType: .string)
    }

    static func copy(image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        let pngData = rep.representation(using: .png, properties: [:])
        let tiffData = rep.tiffRepresentation
        // Declare both TIFF (legacy AppKit consumers) and PNG (modern
        // pickers, web targets). Apps will pick whichever they prefer.
        var types: [NSPasteboard.PasteboardType] = []
        if tiffData != nil { types.append(.tiff) }
        if pngData != nil  { types.append(.png) }
        pb.declareTypes(types, owner: nil)
        if let tiffData { pb.setData(tiffData, forType: .tiff) }
        if let pngData  { pb.setData(pngData,  forType: .png)  }
    }
}
