import Cocoa
import Vision

/// Runs Vision's text recognition over a CGImage and returns the recognised
/// lines in reading order.
///
/// Returns an empty array when nothing is found — the caller's signal to
/// switch to image-paste mode rather than text-paste mode.
///
/// Reading order: Vision returns observations whose `boundingBox` is in
/// normalised image coordinates with origin bottom-left. We sort them top
/// to bottom, then left to right within rough "lines" (boxes whose y-extents
/// overlap significantly). For tight column-shaped selections this collapses
/// neatly to a single column of text, one line per row.
///
/// Languages: derived from `Locale.preferredLanguages` intersected with
/// Vision's supported set, with English always appended as a fallback so
/// an English document on a non-English-locale machine still OCRs cleanly.
/// Computed once at process start (cheap, but no need to recompute per
/// capture) — relaunch CopyLens if you change system languages.
enum OCRService {

    static func recognize(_ image: CGImage) async -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = preferredLanguages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            clog("OCRService: VN perform failed — \(error)")
            return []
        }

        guard let observations = request.results, !observations.isEmpty else {
            return []
        }

        let sorted = observations.sorted { a, b in
            let ay = a.boundingBox.midY
            let by = b.boundingBox.midY
            // 1.5 % of image height is a generous "same line" tolerance —
            // wider than typical line leading but narrower than paragraph
            // gaps, so multi-line columns stay in row order.
            if abs(ay - by) > 0.015 {
                return ay > by   // higher midY = nearer top of image
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        return sorted.compactMap { $0.topCandidates(1).first?.string }
    }

    /// Human-readable summary of the language list, for the Settings UI.
    /// Example: `"en-GB, fr-FR, en-US"`.
    static func summarisedLanguages() -> String {
        preferredLanguages.joined(separator: ", ")
    }

    // MARK: - Language resolution

    /// Cached at process start. Vision's supported list is fixed at
    /// runtime, so there's no need to recompute on every call.
    private static let preferredLanguages: [String] = computePreferredLanguages()

    private static func computePreferredLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]

        var picked: [String] = []
        for pref in Locale.preferredLanguages {
            // Exact match first (e.g. preferred="en-GB" matches supported="en-GB"
            // when Vision adds it), else base-language match (e.g. preferred="en-GB"
            // → supported="en-US" via base="en").
            let exact = supported.first { $0.caseInsensitiveCompare(pref) == .orderedSame }
            let baseLanguageOfPref = baseLanguageCode(pref)
            let prefixMatch = supported.first {
                baseLanguageCode($0).caseInsensitiveCompare(baseLanguageOfPref) == .orderedSame
            }
            if let match = exact ?? prefixMatch, !picked.contains(match) {
                picked.append(match)
            }
        }

        // Always end with English so a non-English-locale machine that
        // OCRs an English document still gets text back. Skip if English
        // is already in the list (avoid duplicating).
        if !picked.contains(where: { baseLanguageCode($0).caseInsensitiveCompare("en") == .orderedSame }) {
            if let en = supported.first(where: { baseLanguageCode($0).caseInsensitiveCompare("en") == .orderedSame }) {
                picked.append(en)
            }
        }

        if picked.isEmpty { picked = ["en-US"] }
        clog("OCRService: languages=\(picked) (supported=\(supported.count))")
        return picked
    }

    /// Returns the base language code ("en" from "en-GB", "zh" from
    /// "zh-Hans"). Vision identifiers and locale identifiers both use
    /// hyphens between language and region/script.
    private static func baseLanguageCode(_ identifier: String) -> String {
        identifier.split(separator: "-").first.map(String.init) ?? identifier
    }
}
