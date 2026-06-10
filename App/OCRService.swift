import Cocoa
import Vision
import CoreImage

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

    /// `sourceScale` is the capturing display's `backingScaleFactor`. On a
    /// Retina/5K display (≥ 2.0) the native capture already gives Vision
    /// ~28–32 px glyphs and we recognise it as-is. On a sub-Retina display
    /// (< 2.0) glyphs land around 10–12 px, well under the recogniser's
    /// comfortable range, so we hand Vision an enhanced copy (Lanczos
    /// upscale + light contrast + unsharp mask) and drop the small-text
    /// floor. The native image is untouched — the caller still pastes that
    /// when no text is found.
    /// One recognised word with its bounding box in Vision's normalised,
    /// bottom-left-origin image space. Fed to `TableDetector` to reconstruct
    /// column/row structure geometrically.
    struct PositionedWord {
        let text: String
        let box: CGRect
    }

    /// Result of a recognition pass.
    /// - `lines`: reading-order observation strings (the plain-text path).
    /// - `words`: every word with its box (the table-detection path).
    struct OCRResult {
        let lines: [String]
        let words: [PositionedWord]

        var isEmpty: Bool { lines.isEmpty }
    }

    static func recognize(_ image: CGImage, sourceScale: CGFloat = 2.0) async -> OCRResult {
        let lowRes = sourceScale < 2.0
        let ocrImage: CGImage
        if lowRes {
            // Bring the effective density up to ~3× (1.0 → 3×, 1.5 → 2×).
            let factor = max(1.0, 3.0 / sourceScale)
            ocrImage = enhancedForOCR(image, upscale: factor) ?? image
            clog("OCRService: low-res source (scale \(sourceScale)) — enhanced \(image.width)×\(image.height) → \(ocrImage.width)×\(ocrImage.height)")
        } else {
            ocrImage = image
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = preferredLanguages
        if lowRes {
            // minimumTextHeight is a fraction of image height, so upscaling
            // doesn't change it — lower the floor explicitly so a small
            // caption inside a wider selection isn't discarded. Also pin the
            // newest recogniser revision available. Both are scoped to the
            // low-res path so the Retina behaviour is byte-for-byte unchanged.
            request.minimumTextHeight = 0
            if let newest = VNRecognizeTextRequest.supportedRevisions.max() {
                request.revision = newest
            }
        }

        let handler = VNImageRequestHandler(cgImage: ocrImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            clog("OCRService: VN perform failed — \(error)")
            return OCRResult(lines: [], words: [])
        }

        guard let observations = request.results, !observations.isEmpty else {
            return OCRResult(lines: [], words: [])
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

        let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
        let words = sorted.flatMap { positionedWords(in: $0) }
        return OCRResult(lines: lines, words: words)
    }

    /// Breaks an observation's top candidate into whitespace-delimited words,
    /// each tagged with its own bounding box via `boundingBox(for:)`. Vision
    /// sometimes returns a whole table row as one observation and sometimes
    /// one observation per cell — working at word granularity makes the
    /// downstream column reconstruction robust to both.
    private static func positionedWords(in observation: VNRecognizedTextObservation) -> [PositionedWord] {
        guard let candidate = observation.topCandidates(1).first else { return [] }
        let string = candidate.string
        var result: [PositionedWord] = []
        var index = string.startIndex
        while index < string.endIndex {
            if string[index].isWhitespace {
                index = string.index(after: index)
                continue
            }
            let wordStart = index
            var wordEnd = index
            while wordEnd < string.endIndex, !string[wordEnd].isWhitespace {
                wordEnd = string.index(after: wordEnd)
            }
            let range = wordStart..<wordEnd
            let text = String(string[range])
            // boundingBox(for:) maps a character range back to image space.
            // Fall back to the whole-observation box if it can't (rare); that
            // word then can't be column-split, which is the acceptable
            // degenerate case.
            if let boxObs = try? candidate.boundingBox(for: range) {
                result.append(PositionedWord(text: text, box: boxObs.boundingBox))
            } else {
                result.append(PositionedWord(text: text, box: observation.boundingBox))
            }
            index = wordEnd
        }
        return result
    }

    // MARK: - Low-resolution enhancement

    /// GPU-backed Core Image context, created once. Reused across captures —
    /// building a CIContext per call is expensive.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Produces an OCR-friendly copy of a low-DPI capture: a Lanczos upscale
    /// (good-quality interpolation), a small contrast lift, and an unsharp
    /// mask to restore the edge contrast that sub-pixel rendering and the
    /// interpolation soften. Upscaling can't add detail the framebuffer never
    /// had, but a larger, crisper glyph blob is what Vision's detector wants —
    /// and it lifts small text clear of the recogniser's internal floor.
    ///
    /// Returns nil if any filter or the final render fails, so the caller
    /// falls back to the unmodified image rather than dropping the capture.
    private static func enhancedForOCR(_ cgImage: CGImage, upscale: CGFloat) -> CGImage? {
        var working = CIImage(cgImage: cgImage)

        guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        lanczos.setValue(working, forKey: kCIInputImageKey)
        lanczos.setValue(upscale, forKey: kCIInputScaleKey)
        lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let scaled = lanczos.outputImage else { return nil }
        working = scaled

        if let contrast = CIFilter(name: "CIColorControls") {
            contrast.setValue(working, forKey: kCIInputImageKey)
            contrast.setValue(1.1, forKey: kCIInputContrastKey)
            if let out = contrast.outputImage { working = out }
        }

        if let unsharp = CIFilter(name: "CIUnsharpMask") {
            unsharp.setValue(working, forKey: kCIInputImageKey)
            unsharp.setValue(1.6, forKey: kCIInputRadiusKey)
            unsharp.setValue(0.7, forKey: kCIInputIntensityKey)
            if let out = unsharp.outputImage { working = out }
        }

        let extent = working.extent
        guard !extent.isInfinite, !extent.isNull, !extent.isEmpty else { return nil }
        return ciContext.createCGImage(working, from: extent)
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
