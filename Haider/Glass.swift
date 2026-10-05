import SwiftUI

/// The glass idiom, lifted from ClankaSpeedTest so this app belongs to the same
/// family: frosted material, a top-lit highlight, one soft shadow, no outlines.
///
/// The field is the content and it lives *behind* the glass — everything the
/// user touches floats over it, so the interface never competes with the thing
/// they are actually making.
extension View {

    /// A frosted panel: material, top-lit wash, soft drop shadow.
    func glassSurface(_ radius: CGFloat = 22, tint: Color = .clear, strength: Double = 0) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.18), .white.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom)
                            )
                    }
                    .overlay {
                        if strength > 0 {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(tint.opacity(strength))
                        }
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 5)
    }

    /// A frosted pill, for anything that sits inline.
    func glassPill(tint: Color = .clear, strength: Double = 0) -> some View {
        self
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule().fill(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .white.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom)
                        )
                    }
                    .overlay {
                        if strength > 0 { Capsule().fill(tint.opacity(strength)) }
                    }
            }
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 3)
    }
}

/// A single hairline, the only border this app draws.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Snail.line.opacity(0.7))
            .frame(height: 0.5)
    }
}