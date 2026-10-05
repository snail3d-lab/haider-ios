import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import CoreGraphics
import CoreText

/// The motion field: two counter-scrolling noise populations, plus the mask that
/// decides which shows through.
///
/// This is the iOS port of the desktop codec. The maths is identical; only the
/// container changed. Both populations share one bit density, so a single frame
/// is statistically uniform and the mask is invisible in a still. The words come
/// from the *relative* motion of the two populations, which human vision groups
/// by common fate and a frame-sampling model simply does not see.
final class MotionField {

    struct Grid {
        let cols: Int      // dot cells across
        let rows: Int      // dot cells down
        let dot: Int       // output pixels per dot cell
    }

    private(set) var fore: [UInt8]
    private(set) var back: [UInt8]
    private(set) var mask: [UInt8]
    let grid: Grid

    /// Noise block edge in dot cells. The single most important legibility knob:
    /// at 1 every pixel decorrelates the instant the field scrolls, and a human
    /// sees flicker rather than words. 3-6 is the readable range.
    let speckle: Int
    /// Fraction of white blocks. 0.5 is the tested default.
    let density: Double

    init(grid: Grid, speckle: Int = 4, density: Double = 0.5, seed: UInt64 = 7) {
        self.grid = grid
        self.speckle = max(1, speckle)
        self.density = min(1, max(0, density))
        self.fore = Self.noise(cols: grid.cols, rows: grid.rows,
                               speckle: self.speckle, density: self.density, seed: seed)
        self.back = Self.noise(cols: grid.cols, rows: grid.rows,
                               speckle: self.speckle, density: self.density, seed: seed &+ 1)
        self.mask = [UInt8](repeating: 0, count: grid.cols * grid.rows)
    }

    /// Regenerate the noise with a new seed, so a user can reroll the field.
    func reseed(_ seed: UInt64) {
        fore = Self.noise(cols: grid.cols, rows: grid.rows,
                          speckle: speckle, density: density, seed: seed)
        back = Self.noise(cols: grid.cols, rows: grid.rows,
                          speckle: speckle, density: density, seed: seed &+ 1)
    }

    // MARK: - noise

    /// Independent random blocks. SplitMix64 keeps this reproducible across
    /// launches without pulling in a heavier generator.
    private static func noise(cols: Int, rows: Int, speckle: Int, density: Double,
                              seed: UInt64) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: cols * rows)
        if speckle == 1 {
            var state = seed
            for i in 0..<out.count {
                out[i] = nextDouble(&state) < density ? 1 : 0
            }
            return out
        }
        let bc = cols / speckle + 1
        let br = rows / speckle + 1
        var coarse = [UInt8](repeating: 0, count: bc * br)
        var state = seed
        for i in 0..<coarse.count {
            coarse[i] = nextDouble(&state) < density ? 1 : 0
        }
        for y in 0..<rows {
            let by = y / speckle
            for x in 0..<cols {
                out[y * cols + x] = coarse[by * bc + x / speckle]
            }
        }
        return out
    }

    private static func nextDouble(_ state: inout UInt64) -> Double {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) * (1.0 / 9007199254740992.0)
    }

    // MARK: - text mask

    /// Typeset `message` and rasterise it to a grid-sized mask.
    ///
    /// The font is grown until the block no longer fits, then the last size that
    /// did is kept — so a message always fills as much of the frame as it can
    /// without clipping. Hard newlines are honoured; soft wrapping is measured.
    /// Typeset into a horizontal band of the field. When a QR is in the clip the
    /// text takes the top half and the code takes the bottom, so the two never
    /// overlap — the same split the desktop storyboards use.
    @discardableResult
    func setText(_ message: String, margin: Double = 0.10,
                 frac: Double = 1.0, atTop: Bool = true) -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = [UInt8](repeating: 0, count: grid.cols * grid.rows)
        guard !text.isEmpty else { mask = out; return true }

        // The band: a sub-grid the text is typeset into, then offset into place.
        let bandRows = max(8, Int(Double(grid.rows) * min(max(frac, 0.2), 1.0)))
        let bandOffset = (frac >= 1.0 || atTop) ? 0 : grid.rows - bandRows

        let cw = CGFloat(grid.cols)
        let ch = CGFloat(bandRows)
        let inset = min(cw, ch) * CGFloat(margin)
        let avail = CGSize(width: cw - inset * 2, height: ch - inset * 2)

        let logical = text.replacingOccurrences(of: "\\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !logical.isEmpty else { mask = out; return true }

        func wrap(_ lines: [String], font: CTFont) -> [String] {
            var result: [String] = []
            for line in lines {
                var current = ""
                for word in line.split(separator: " ").map(String.init) {
                    let trial = current.isEmpty ? word : current + " " + word
                    if current.isEmpty || width(trial, font: font) <= avail.width {
                        current = trial
                    } else {
                        result.append(current)
                        current = word
                    }
                }
                result.append(current)
            }
            return result.filter { !$0.isEmpty }
        }

        var best: (CTFont, [String], CGFloat)?
        var size: CGFloat = 4
        while size < ch {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let lines = wrap(logical, font: font)
            let leading = lineHeight(font)
            if leading * CGFloat(lines.count) > avail.height { break }
            if lines.contains(where: { width($0, font: font) > avail.width }) { break }
            best = (font, lines, leading)
            size += max(1, size * 0.08)
        }
        guard let (font, lines, leading) = best else {
            mask = out
            return false
        }

        // Draw into the OS's own text system, then threshold. Rendering through
        // CoreGraphics means kerning and glyph shapes are the real thing rather
        // than an approximation.
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: grid.cols * bandRows)
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress,
                                      width: grid.cols, height: bandRows,
                                      bitsPerComponent: 8,
                                      bytesPerRow: grid.cols,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setFillColor(gray: 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))

            // CoreGraphics puts the origin bottom-left; the mask grid is
            // top-left, so convert once here rather than flipping every type.
            let blockHeight = leading * CGFloat(lines.count)
            var baseline = (ch - blockHeight) / 2 + leading * 0.78
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.setShouldSmoothFonts(false)
            ctx.setShouldAntialias(false)
            for line in lines {
                let lineWidth = width(line, font: font)
                let x = (cw - lineWidth) / 2
                let y = ch - baseline
                let attributed = NSAttributedString(string: line, attributes: [
                    .font: font,
                    .foregroundColor: CGColor(gray: 1, alpha: 1),
                ])
                let ctLine = CTLineCreateWithAttributedString(attributed)
                ctx.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(ctLine, ctx)
                baseline += leading
            }
        }
        for y in 0..<bandRows {
            let dst = bandOffset + y
            guard dst < grid.rows else { break }
            for x in 0..<grid.cols where pixels[y * grid.cols + x] > 110 {
                out[dst * grid.cols + x] = 1
            }
        }
        mask = out
        return true
    }

    private func width(_ string: String, font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        return CGFloat(CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(attributed), nil, nil, nil))
    }

    private func lineHeight(_ font: CTFont) -> CGFloat {
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        return (ascent + descent + leading) * 1.06
    }
}