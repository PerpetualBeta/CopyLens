import Foundation
import CoreGraphics

/// Reconstructs a tabular grid from positioned OCR words.
///
/// The approach is a geometric "X-Y cut":
///   • Rows come from clustering words by vertical centre (`midY`).
///   • Columns come from the vertical whitespace corridors left uncovered
///     when every word's horizontal extent is projected onto the x-axis and
///     merged. A corridor that no word in *any* row crosses is a column
///     boundary. Words within a multi-word cell don't create false columns,
///     because the gaps between them are filled by other rows' text.
///
/// Returns `nil` when the region isn't convincingly tabular, so the caller
/// falls back to the plain-text path. Conservative by design — a stray
/// two-column layout shouldn't be force-fit into a grid.
enum TableDetector {

    struct Table {
        let rows: [[String]]
        var rowCount: Int { rows.count }
        var columnCount: Int { rows.first?.count ?? 0 }
    }

    static func detect(_ words: [OCRService.PositionedWord]) -> Table? {
        // Need a few words before any grid talk is meaningful.
        guard words.count >= 4 else { return nil }

        let rows = clusterRows(words)
        guard rows.count >= 2 else { return nil }

        let columns = columnIntervals(words)
        // ≥ 2 columns to be a table; an absurd count means we carved up prose.
        guard columns.count >= 2, columns.count <= 24 else { return nil }

        var grid: [[String]] = []
        for row in rows {
            var cells = [String](repeating: "", count: columns.count)
            for word in row.sorted(by: { $0.box.minX < $1.box.minX }) {
                let col = columnIndex(for: word.box, columns: columns)
                cells[col] = cells[col].isEmpty ? word.text : cells[col] + " " + word.text
            }
            grid.append(cells)
        }

        // A real table has most rows spanning at least two columns. Prose and
        // single-column lists fail this and fall back to plain text.
        let multiCellRows = grid.filter { $0.filter { !$0.isEmpty }.count >= 2 }.count
        guard Double(multiCellRows) >= Double(grid.count) * 0.6 else { return nil }

        return Table(rows: grid)
    }

    // MARK: - Rows

    private static func clusterRows(_ words: [OCRService.PositionedWord]) -> [[OCRService.PositionedWord]] {
        let sorted = words.sorted { $0.box.midY > $1.box.midY }
        let heights = words.map { $0.box.height }.sorted()
        let medianHeight = heights[heights.count / 2]
        // Same row if vertical centres sit within ~60 % of a line's height.
        let tolerance = max(0.008, medianHeight * 0.6)

        var rows: [[OCRService.PositionedWord]] = []
        for word in sorted {
            if let lastIndex = rows.indices.last {
                let refY = rows[lastIndex].map { $0.box.midY }.reduce(0, +) / CGFloat(rows[lastIndex].count)
                if abs(word.box.midY - refY) <= tolerance {
                    rows[lastIndex].append(word)
                    continue
                }
            }
            rows.append([word])
        }
        return rows
    }

    // MARK: - Columns

    private static func columnIntervals(_ words: [OCRService.PositionedWord]) -> [ClosedRange<CGFloat>] {
        let intervals = words
            .map { $0.box.minX...$0.box.maxX }
            .sorted { $0.lowerBound < $1.lowerBound }

        // Words whose x-extents touch (within a hair) belong to the same
        // column band; a clear gap starts a new band. The pad keeps tightly
        // adjacent words merged without bridging genuine inter-column gaps.
        let pad: CGFloat = 0.004
        var merged: [ClosedRange<CGFloat>] = []
        for interval in intervals {
            if let last = merged.last, interval.lowerBound <= last.upperBound + pad {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, interval.upperBound)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func columnIndex(for box: CGRect, columns: [ClosedRange<CGFloat>]) -> Int {
        let x = box.midX
        for (index, column) in columns.enumerated() where column.contains(x) {
            return index
        }
        // Outside every band (rare): snap to the nearest by edge distance.
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, column) in columns.enumerated() {
            let distance = x < column.lowerBound ? column.lowerBound - x : x - column.upperBound
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}
