import CoreGraphics
import CoreText
import Foundation
import UIKit

/// Scores a finger-drawn kana against its target glyph for Write practice, using
/// symmetric **chamfer distance** (how far each ink pixel is from the other shape's
/// nearest ink — tolerant of handwriting wobble) plus a zone-density term (whether
/// the ink mass sits in the same regions). Shapes are normalized per-axis, so
/// position, size, and proportions don't matter.
enum KanaSketch {
    /// The bundled stroke-order font — the exact shape shown as the on-screen
    /// tracing template, so it must be a scoring template too. Its baked-in
    /// stroke-number digits are stripped in `glyphGrid` before matching.
    private static let strokeOrderFont = "KanjiStrokeOrders"

    /// Template fonts: the traced stroke-order font, print (Hiragino), rounded, and
    /// the textbook fonts (教科書体: YuKyokasho, Klee) whose letterforms match how
    /// kana are actually handwritten. Missing fonts fall back through CoreText's
    /// cascade, which is harmless.
    private static let templateFonts = [
        strokeOrderFont,
        "YuKyokasho-Medium", "Klee-Medium", "TsukushiARoundGothic-Regular", "HiraginoSans-W6",
    ]

    /// 0–100 score of how closely the strokes match the target glyph — the best
    /// (lowest-distance) comparison across the template fonts wins, so both print
    /// and handwritten letterforms count as a good match. Drawing the wrong number
    /// of strokes costs 10 points each: shape matching alone can't tell a one-swipe
    /// scribble from properly ordered strokes.
    static func matchScore(strokes: [[CGPoint]], glyph: String,
                           expectedStrokes: Int? = nil) async -> Int? {
        await Task.detached { () -> Int? in
            guard let user = strokeGrid(strokes) else { return nil }
            var bestD = Double.infinity
            for font in templateFonts {
                guard let template = glyphGrid(glyph, font: font) else { continue }
                bestD = min(bestD, distance(user, template))
            }
            guard bestD.isFinite else { return nil }
            // Gentle curve: a faithful trace lands in the mid-90s — encouraging
            // practice feedback, not a strict grade.
            var score = 100 - bestD * 3.5
            if let expected = expectedStrokes, expected > 0 {
                score -= Double(abs(strokes.count - expected)) * 10
            }
            return max(0, min(100, Int(score.rounded())))
        }.value
    }

    /// Combined shape distance (exposed for tests): chamfer (how far apart the ink
    /// is) plus a zone-density term (whether the ink mass sits in the same regions —
    /// chamfer alone under-punishes a missing stroke, e.g. に matching ロ).
    static func distance(_ a: [Bool], _ b: [Bool]) -> Double {
        chamfer(a, distanceTransform(a), b, distanceTransform(b))
            + 5 * zoneDiff(zones(a), zones(b))
    }

    /// Fraction of total ink per 6×6 region (sums to 1).
    static func zones(_ g: [Bool]) -> [Double] {
        let z = 6
        var counts = [Double](repeating: 0, count: z * z)
        var total = 0.0
        for y in 0..<n {
            for x in 0..<n where g[y * n + x] {
                counts[(y * z / n) * z + (x * z / n)] += 1
                total += 1
            }
        }
        return total > 0 ? counts.map { $0 / total } : counts
    }

    /// L1 difference between two zone histograms (0 = identical mass layout, max 2).
    static func zoneDiff(_ a: [Double], _ b: [Double]) -> Double {
        zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) }
    }

    // MARK: - bitmap pipeline (all CoreGraphics, safe off the main thread)

    private static let n = 48          // matching grid resolution
    private static let margin = 0.12   // whitespace around the normalized glyph
    private static let big = 160       // raw glyph raster size (pre-normalization)

    private static func grayContext(_ size: Int) -> CGContext? {
        CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
    }

    private static func pixels(_ ctx: CGContext) -> [Bool] {
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
        let (w, h, row) = (ctx.width, ctx.height, ctx.bytesPerRow)
        var out = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w { out[y * w + x] = data[y * row + x] > 127 }
        }
        return out
    }

    /// Rasterize strokes into an n×n grid, stretched per-axis to fill the grid
    /// (minus a margin) — position, scale, and proportions are all normalized away.
    static func strokeGrid(_ strokes: [[CGPoint]]) -> [Bool]? {
        let pts = strokes.flatMap { $0 }
        guard pts.count > 1 else { return nil }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let (minX, maxX, minY, maxY) = (xs.min()!, xs.max()!, ys.min()!, ys.max()!)
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let m = Double(n) * margin
        let inner = Double(n) - 2 * m

        func map(_ p: CGPoint) -> CGPoint {
            let x = m + Double(p.x - minX) / Double(w) * inner
            let y = m + Double(p.y - minY) / Double(h) * inner
            return CGPoint(x: x, y: Double(n) - y)   // flip into CG orientation
        }

        guard let ctx = grayContext(n) else { return nil }
        ctx.setStrokeColor(gray: 1, alpha: 1)
        ctx.setLineWidth(CGFloat(n) * 0.09)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes where stroke.count > 1 {
            ctx.move(to: map(stroke[0]))
            for p in stroke.dropFirst() { ctx.addLine(to: map(p)) }
            ctx.strokePath()
        }
        return pixels(ctx)
    }

    /// Rasterize a glyph into the raw `big`×`big` working bitmap (pre-normalization).
    private static func rawGlyph(_ glyph: String, font fontName: String) -> [Bool]? {
        guard let ctx = grayContext(big) else { return nil }
        // Multi-char glyphs (combos like びゃ) must shrink or they'd draw past the
        // bitmap's right edge and the template would be a clipped half-kana.
        let font = CTFontCreateWithName(fontName as CFString, glyph.count > 1 ? 64 : 110, nil)
        let attr = NSAttributedString(string: glyph, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        ctx.textPosition = CGPoint(x: 8, y: 35)
        CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
        return pixels(ctx)
    }

    /// Render a kana glyph (system Japanese font) and normalize it into the same
    /// per-axis-stretched n×n grid as the strokes.
    static func glyphGrid(_ glyph: String, font fontName: String = "HiraginoSans-W6") -> [Bool]? {
        guard var raw = rawGlyph(glyph, font: fontName) else { return nil }
        // The stroke-order font bakes tiny numbered digits into each glyph — they
        // are annotations, not ink to match, so strip them before normalizing.
        if fontName == strokeOrderFont { stripTinyComponents(&raw, size: big) }

        // bounding box of lit pixels
        var minX = big, maxX = -1, minY = big, maxY = -1
        for y in 0..<big {
            for x in 0..<big where raw[y * big + x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        let bw = Double(maxX - minX), bh = Double(maxY - minY)
        let m = Double(n) * margin
        let inner = Double(n) - 2 * m

        // nearest-neighbor resample, stretched per-axis exactly like the strokes
        var out = [Bool](repeating: false, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let u = (Double(x) - m) / inner
                let v = (Double(y) - m) / inner
                guard u >= 0, u < 1, v >= 0, v < 1 else { continue }
                let sx = minX + Int(u * bw)
                let sy = minY + Int(v * bh)
                if raw[sy * big + sx] { out[y * n + x] = true }
            }
        }
        return out
    }

    /// Erase connected components with a bounding box smaller than `maxDim`,
    /// returning how many were erased. Default 6 is measured on the stroke-order
    /// font at its `big`-raster size: number digits are ≤4×5 while the smallest
    /// real ink (dakuten/handakuten marks, short stroke fragments) is ≥8×6 — so
    /// this removes every digit and never touches actual strokes, and the count
    /// (one digit per stroke) is the glyph's stroke count. Callers rendering at a
    /// different raster size pass a `maxDim` scaled to match.
    @discardableResult
    static func stripTinyComponents(_ g: inout [Bool], size: Int, maxDim: Int = 6) -> Int {
        var erased = 0
        var seen = [Bool](repeating: false, count: g.count)
        for start in 0..<g.count where g[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var member: [Int] = []
            var minX = size, maxX = 0, minY = size, maxY = 0
            while let i = stack.popLast() {
                member.append(i)
                let x = i % size, y = i / size
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                for dy in -1...1 {
                    for dx in -1...1 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < size, ny >= 0, ny < size else { continue }
                        let j = ny * size + nx
                        if g[j] && !seen[j] { seen[j] = true; stack.append(j) }
                    }
                }
            }
            if maxX - minX < maxDim && maxY - minY < maxDim {
                for i in member { g[i] = false }
                erased += 1
            }
        }
        return erased
    }

    // MARK: - on-screen trace template (Write mode)

    /// Renders the target glyph as a plain trace image for the on-screen template —
    /// the stroke-order font's shape with its numbered annotations stripped, so
    /// learners see stroke shapes without digit clutter. Unlike `glyphGrid` (which
    /// stretches per-axis for scoring), this preserves aspect ratio so the glyph
    /// isn't distorted. Returns a template-mode `UIImage` (tint via `.foregroundStyle`).
    static func strokeTemplateImage(_ glyph: String, pixelSize: Int) async -> UIImage? {
        await Task.detached { () -> UIImage? in
            guard !glyph.isEmpty, pixelSize > 0,
                  var mask = rasterizeAspectFit(glyph, font: strokeOrderFont, pixelSize: pixelSize)
            else { return nil }
            // Scale the digit-stripping threshold from the `big`-raster calibration.
            let maxDim = max(2, Int((6.0 / Double(big)) * Double(pixelSize)))
            stripTinyComponents(&mask, size: pixelSize, maxDim: maxDim)

            guard let ctx = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let buf = ctx.data?.assumingMemoryBound(to: UInt8.self)
            else { return nil }
            let bpr = ctx.bytesPerRow
            for y in 0..<pixelSize {
                for x in 0..<pixelSize {
                    let o = y * bpr + x * 4
                    buf[o] = 255; buf[o + 1] = 255; buf[o + 2] = 255
                    buf[o + 3] = mask[y * pixelSize + x] ? 255 : 0
                }
            }
            guard let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg, scale: 1, orientation: .up).withRenderingMode(.alwaysTemplate)
        }.value
    }

    /// Rasterize a glyph into a `pixelSize`×`pixelSize` boolean grid, uniformly
    /// scaled (aspect preserved) to fit with a margin, and centered — for display,
    /// not the per-axis-stretched grid `glyphGrid` builds for matching.
    private static func rasterizeAspectFit(_ glyph: String, font fontName: String,
                                           pixelSize: Int) -> [Bool]? {
        guard let ctx = grayContext(pixelSize) else { return nil }
        let margin = 0.06

        func line(_ fontSize: CGFloat) -> (CTLine, CGRect) {
            let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
            let attr = NSAttributedString(string: glyph, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ])
            let l = CTLineCreateWithAttributedString(attr)
            return (l, CTLineGetBoundsWithOptions(l, .useGlyphPathBounds))
        }

        let probeSize: CGFloat = 200
        let (_, probeBounds) = line(probeSize)
        guard probeBounds.width > 0, probeBounds.height > 0 else { return nil }
        let target = CGFloat(pixelSize) * (1 - 2 * margin)
        let fit = min(target / probeBounds.width, target / probeBounds.height)
        let (finalLine, finalBounds) = line(probeSize * fit)

        ctx.textPosition = CGPoint(
            x: (CGFloat(pixelSize) - finalBounds.width) / 2 - finalBounds.minX,
            y: (CGFloat(pixelSize) - finalBounds.height) / 2 - finalBounds.minY
        )
        CTLineDraw(finalLine, ctx)
        return pixels(ctx)
    }

    // MARK: - chamfer matching

    /// City-block distance transform: distance from each cell to the nearest ink.
    static func distanceTransform(_ g: [Bool]) -> [Double] {
        var d = g.map { $0 ? 0.0 : 1e9 }
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                if x > 0 { d[i] = min(d[i], d[i - 1] + 1) }
                if y > 0 { d[i] = min(d[i], d[i - n] + 1) }
            }
        }
        for y in stride(from: n - 1, through: 0, by: -1) {
            for x in stride(from: n - 1, through: 0, by: -1) {
                let i = y * n + x
                if x < n - 1 { d[i] = min(d[i], d[i + 1] + 1) }
                if y < n - 1 { d[i] = min(d[i], d[i + n] + 1) }
            }
        }
        return d
    }

    /// Mean distance from A's ink to B's nearest ink, plus the reverse. 0 = identical.
    private static func chamfer(_ a: [Bool], _ dtA: [Double],
                                _ b: [Bool], _ dtB: [Double]) -> Double {
        var sumAB = 0.0, ca = 0, sumBA = 0.0, cb = 0
        for i in 0..<a.count {
            if a[i] { sumAB += dtB[i]; ca += 1 }
            if b[i] { sumBA += dtA[i]; cb += 1 }
        }
        guard ca > 0, cb > 0 else { return .infinity }
        return sumAB / Double(ca) + sumBA / Double(cb)
    }
}
