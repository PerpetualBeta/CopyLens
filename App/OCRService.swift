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
    /// When the user's system preference has an exact Vision match, just
    /// shows the Vision identifier (e.g. `"fr-FR"`). When the system pref
    /// doesn't have a Vision counterpart and we fell back to the
    /// base-language match, shows the mapping (e.g. `"en-US (from en-GB)"`)
    /// — Vision doesn't ship an en-GB recogniser, so an en-GB system gets
    /// en-US for OCR, and this surface makes that visible.
    static func summarisedLanguages() -> String {
        mappings.map { m -> String in
            if let pref = m.userPref, pref.caseInsensitiveCompare(m.vision) != .orderedSame {
                return "\(m.vision) (from \(pref))"
            }
            return m.vision
        }.joined(separator: ", ")
    }

    // MARK: - Language resolution

    /// One row per Vision language CopyLens will ask the recogniser to
    /// consider, paired with the user-preference that produced it (or
    /// `nil` when the language is the English fallback we always append).
    private struct LanguageMapping {
        let vision: String
        let userPref: String?
    }

    /// Cached at process start. Vision's supported list is fixed at
    /// runtime, so there's no need to recompute on every call.
    private static let mappings: [LanguageMapping] = computeMappings()
    private static let preferredLanguages: [String] = mappings.map(\.vision)

    private static func computeMappings() -> [LanguageMapping] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = (try? request.supportedRecognitionLanguages()) ?? ["en-US"]

        var result: [LanguageMapping] = []
        var seenVision = Set<String>()

        for pref in Locale.preferredLanguages {
            // Exact match first (e.g. preferred="en-GB" matches supported="en-GB"
            // if Vision ever adds it), else base-language match (e.g.
            // preferred="en-GB" → supported="en-US" via base="en").
            let exact = supported.first { $0.caseInsensitiveCompare(pref) == .orderedSame }
            let baseLanguageOfPref = baseLanguageCode(pref)
            let prefixMatch = supported.first {
                baseLanguageCode($0).caseInsensitiveCompare(baseLanguageOfPref) == .orderedSame
            }
            if let match = exact ?? prefixMatch, !seenVision.contains(match) {
                result.append(LanguageMapping(vision: match, userPref: pref))
                seenVision.insert(match)
            }
        }

        // Always end with English so a non-English-locale machine that
        // OCRs an English document still gets text back. Skip if English
        // is already in the list (avoid duplicating). No userPref because
        // this entry isn't driven by Locale.
        if !result.contains(where: { baseLanguageCode($0.vision).caseInsensitiveCompare("en") == .orderedSame }) {
            if let en = supported.first(where: { baseLanguageCode($0).caseInsensitiveCompare("en") == .orderedSame }) {
                result.append(LanguageMapping(vision: en, userPref: nil))
            }
        }

        if result.isEmpty { result = [LanguageMapping(vision: "en-US", userPref: nil)] }
        clog("OCRService: mappings=\(result.map { "\($0.vision)←\($0.userPref ?? "fallback")" }) (supported=\(supported.count))")
        return result
    }

    /// Returns the base language code ("en" from "en-GB", "zh" from
    /// "zh-Hans"). Vision identifiers and locale identifiers both use
    /// hyphens between language and region/script.
    private static func baseLanguageCode(_ identifier: String) -> String {
        identifier.split(separator: "-").first.map(String.init) ?? identifier
    }
}
