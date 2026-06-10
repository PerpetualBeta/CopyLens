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

    /// Writes a recognised table in two representations at once:
    ///   • `.html` — a real `<table>`, so rich targets (Numbers, Excel, Word,
    ///     Pages, Mail) paste it as a structured grid of cells.
    ///   • `.string` — tab-separated values, so spreadsheets that read TSV
    ///     split it into cells and plain-text editors get readable columns.
    /// Paste targets pick whichever representation they understand best.
    static func copy(table: TableDetector.Table) {
        let tsv = table.rows
            .map { $0.joined(separator: "\t") }
            .joined(separator: "\n")
        let html = htmlTable(table)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.html, .string], owner: nil)
        pb.setString(html, forType: .html)
        pb.setString(tsv, forType: .string)
    }

    private static func htmlTable(_ table: TableDetector.Table) -> String {
        var body = ""
        for row in table.rows {
            let cells = row.map { "<td>\(escapeHTML($0))</td>" }.joined()
            body += "<tr>\(cells)</tr>"
        }
        return "<table>\(body)</table>"
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
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
