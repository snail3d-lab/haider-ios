import Foundation
import CoreGraphics

// Plain-swift harness: verifies the iOS port keeps the property the whole
// product rests on. A single frame must be statistically uniform whether or not
// a mask is set — if the mask showed up in a still, there would be nothing to
// sell.
//
//   swiftc -O MotionField.swift verify_field.swift -o verify && ./verify
//
// MotionField's text typesetting needs CoreText, which is available on macOS,
// so this compiles the real file rather than a copy.

func litFraction(_ bytes: [UInt8], mask: [UInt8]?, wantMasked: Bool?) -> Double {
    var lit = 0, total = 0
    for i in bytes.indices {
        guard let mask else {
            lit += bytes[i] != 0 ? 1 : 0
            total += 1
            continue
        }
        let isMasked = mask[i] != 0
        if let wantMasked, isMasked != wantMasked { continue }
        lit += bytes[i] != 0 ? 1 : 0
        total += 1
    }
    return total == 0 ? 0 : Double(lit) / Double(total)
}

let grid = MotionField.Grid(cols: 216, rows: 384, dot: 5)
let field = MotionField(grid: grid, speckle: 4, density: 0.5, seed: 7)

print("grid \(grid.cols)x\(grid.rows) @ dot \(grid.dot) = \(grid.cols * grid.dot)x\(grid.rows * grid.dot)")

// 1. No mask: the field itself should sit at the requested density.
let bareFore = litFraction(field.fore, mask: nil, wantMasked: nil)
let bareBack = litFraction(field.back, mask: nil, wantMasked: nil)
print(String(format: "no mask   fore %.4f  back %.4f  (expect ~0.5)", bareFore, bareBack))

// 2. With a message: the critical test. Lit density inside the text mask must
//    match the density outside it. Any real gap means the words are visible in
//    a paused frame.
let ok = field.setText("HIDE FROM\nTHE AI")
let ink = field.mask.reduce(0) { $0 + ($1 != 0 ? 1 : 0) }
print("typeset ok: \(ok)  mask covers \(ink) of \(grid.cols * grid.rows) cells "
      + String(format: "(%.2f%%)", 100 * Double(ink) / Double(grid.cols * grid.rows)))

// Composite a frame the way the shader does: masked cells take fore, others back.
var composed = [UInt8](repeating: 0, count: grid.cols * grid.rows)
for row in 0..<grid.rows {
    for col in 0..<grid.cols {
        let i = row * grid.cols + col
        let off = Int((Double(7) * 2.0).rounded())
        let fRow = ((row + off) % grid.rows + grid.rows) % grid.rows
        let bRow = ((row - off) % grid.rows + grid.rows) % grid.rows
        let f = field.fore[fRow * grid.cols + col]
        let b = field.back[bRow * grid.cols + col]
        composed[i] = field.mask[i] != 0 ? f : b
    }
}

let inside = litFraction(composed, mask: field.mask, wantMasked: true)
let outside = litFraction(composed, mask: field.mask, wantMasked: false)
let delta = abs(inside - outside)
print(String(format: "with mask inside %.4f  outside %.4f  delta %.4f", inside, outside, delta))

let pass = delta < 0.01 && abs(bareFore - 0.5) < 0.03 && abs(bareBack - 0.5) < 0.03
print(pass ? "PASS  a single frame is uniform; the mask is invisible in a still"
           : "FAIL  the mask leaks into a still")
exit(pass ? 0 : 1)