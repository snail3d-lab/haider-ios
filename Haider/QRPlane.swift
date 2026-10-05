import Foundation
import CoreImage
import CoreGraphics

/// A QR code biased *into* the field rather than drawn on top of it.
///
/// A reader does not need clean pixels — it averages each module and binarises —
/// so forcing a fraction of cells to the module's own value keeps the code
/// readable in every frame while the rest of the field keeps scrolling. Nothing
/// is drawn over the field, and because both noise populations carry the same
/// bias the text stays just as hidden as before.
///
/// Two things learned the hard way on the desktop build, both encoded here:
///   * both directions must be pushed — light-only leaves dark modules at the
///     field's own 0.5 density, which sits exactly on a reader's threshold and
///     reads as ambiguous;
///   * the push must be strong (0.95 measured for a reliable scan; 0.75 did not
///     scan at all).
enum QRPlane {

    /// 0 = leave the field alone, 1 = force ink (light module), 2 = force paper.
    static let none: UInt8 = 0
    static let light: UInt8 = 1
    static let dark: UInt8 = 2

    /// Decode `url` into a module matrix using the system encoder.
    /// Returns nil if the string is too long to encode.
    static func matrix(for url: String, correction: String = "M") -> [[Bool]]? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.utf8), forKey: "inputMessage")
        filter.setValue(correction, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        // CIImage is in module units; render 1px per module then read it back.
        let n = Int(output.extent.width)
        guard n > 0, n < 200 else { return nil }
        let space = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: n * n)
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: n, height: n,
                                      bitsPerComponent: 8, bytesPerRow: n,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            let ci = CIContext(options: [.useSoftwareRenderer: false])
            guard let cg = ci.createCGImage(output, from: output.extent) else { return }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        }
        // CoreGraphics is bottom-up; the module grid is top-down.
        var grid = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
        for y in 0..<n {
            for x in 0..<n {
                grid[y][x] = pixels[(n - 1 - y) * n + x] < 128   // dark module
            }
        }
        return grid
    }

    /// Build the bias plane at field resolution: `scale` dot cells per module,
    /// centred with the 4-module quiet zone the spec requires, and the given
    /// fraction of cells forced to each module's own value.
    static func plane(url: String,
                      rows: Int, cols: Int,
                      scale: Int = 4,
                      push: Double = 0.95,
                      position: String = "b",
                      bottomInset: Double = 0.0,
                      seed: UInt64 = 0xA11CE) -> [UInt8]? {
        guard let modules = matrix(for: url) else { return nil }
        let n = modules.count
        let side = n * scale
        guard side <= cols, side <= rows else { return nil }

        // `bottomInset` keeps the code clear of anything the host draws over the
        // bottom of the field, such as a floating control row.
        let inset = Int(Double(rows) * min(max(bottomInset, 0), 0.6))
        let y0 = position.contains("t") ? inset
            : (position.contains("b") ? rows - side - inset : (rows - side) / 2)
        let x0 = position.contains("l") ? 0
            : (position.contains("r") ? cols - side : (cols - side) / 2)

        var plane = [UInt8](repeating: none, count: rows * cols)
        var state = seed
        func rnd() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 11) & 0xFFFFFF) / Double(0xFFFFFF)
        }

        for my in 0..<n {
            for mx in 0..<n {
                let value: UInt8 = modules[my][mx] ? dark : light
                for dy in 0..<scale {
                    let y = y0 + my * scale + dy
                    guard y >= 0, y < rows else { continue }
                    for dx in 0..<scale {
                        let x = x0 + mx * scale + dx
                        guard x >= 0, x < cols else { continue }
                        if rnd() < push { plane[y * cols + x] = value }
                    }
                }
            }
        }
        return plane
    }
}