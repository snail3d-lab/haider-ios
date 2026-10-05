import SwiftUI

/// The Snail 3D palette, lifted from snail3d.com and the Mascii app so this
/// product matches the family rather than inventing colour.
///
/// One accent, one job. Lime is spent on the single thing that matters in a
/// region — never on two competing things, and never hashed per item.
enum Snail {
    static let shell = Color(red: 0.043, green: 0.055, blue: 0.047)      // #0B0E0C
    static let panel = Color(red: 0.067, green: 0.090, blue: 0.075)      // #111713
    static let line = Color(red: 0.145, green: 0.204, blue: 0.169)       // #25342B
    static let neutrino = Color(red: 0.949, green: 0.961, blue: 0.933)   // #F2F5EE
    static let dim = Color(red: 0.604, green: 0.659, blue: 0.620)        // #9AA89E
    static let lime = Color(red: 0.639, green: 0.902, blue: 0.208)       // #A3E635
    static let limeDim = Color(red: 0.435, green: 0.612, blue: 0.122)    // #6F9C1F
}

/// The field's ink. These are *not* the Snail palette — they are the product's
/// own material, and the field is the content, so it is allowed its own colour.
/// The interface around it stays Snail; the field is whatever the user picks.
///
/// Both noise populations always paint in the same ink. That is a correctness
/// requirement, not a style choice: two colours would make
/// P(colour A) = mask x density, so the mask could be read off the colour
/// proportions of a single frame and the whole product would stop working.
enum Ink: String, CaseIterable, Identifiable {
    case white, acid, amber, ice, bone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: "White"
        case .acid: "Acid"
        case .amber: "Amber"
        case .ice: "Ice"
        case .bone: "Bone"
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .white: (1.0, 1.0, 1.0)
        case .acid: (0.64, 0.90, 0.21)   // the Snail lime, as material
        case .amber: (1.0, 0.54, 0.09)
        case .ice: (0.56, 0.86, 1.0)
        case .bone: (0.91, 0.89, 0.82)
        }
    }

    var linear: SIMD4<Float> {
        let c = rgb
        return SIMD4(Float(c.0), Float(c.1), Float(c.2), 1)
    }

    /// Paper for a light ink, near-black for a bright one. Chosen by eye so the
    /// field always reads at phone distance in daylight.
    var background: SIMD4<Float> {
        switch self {
        case .white, .acid: SIMD4(0.016, 0.020, 0.016, 1)
        case .amber: SIMD4(0.043, 0.016, 0.0, 1)
        case .ice: SIMD4(0.016, 0.031, 0.055, 1)
        case .bone: SIMD4(0.949, 0.937, 0.910, 1)
        }
    }

    var swiftUIColor: Color {
        let c = rgb
        return Color(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: 1)
    }

    /// The swatch needs a visible ring on both a dark and a light paper.
    var swatchRing: Color {
        self == .bone ? Color.black.opacity(0.25) : Color.white.opacity(0.18)
    }
}