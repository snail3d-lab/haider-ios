import SwiftUI

/// The QR overlay is the premium feature, and its pitch is one sentence: a
/// screenshot of the field shows nothing — except the QR, which still scans. So
/// the code travels even when the words don't.
///
/// Presentation follows the creed: one promise, one price, one button. No
/// feature matrix, no bullets about what you get, no testimonials.
struct PaywallView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Snail.shell.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // The demonstration itself: a QR that survives a screenshot,
                // sitting on a still that shows nothing else.
                QRMark(size: 168)
                    .padding(22)
                    .glassSurface(30)
                    .accessibilityLabel("QR overlay")

                Spacer().frame(height: 34)

                Text("Scan me from a screenshot")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Snail.neutrino)
                    .multilineTextAlignment(.center)

                Text("The words never survive a screenshot. This does.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Snail.dim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 34)

                Spacer()

                Button {
                    // StoreKit wiring lands with the product record; the sheet is
                    // present now so the flow is real from the first build.
                    dismiss()
                } label: {
                    Text("Unlock")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Snail.shell)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Snail.lime, in: Capsule())
                }
                .padding(.horizontal, 26)

                Button("Not now") { dismiss() }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Snail.dim)
                    .padding(.top, 14)

                Spacer().frame(height: 26)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// A quiet, drawn QR placeholder — three finder squares and a field of modules,
/// no external image. Replace with the real code once the generator lands.
struct QRMark: View {
    var size: CGFloat

    private let n = 21

    var body: some View {
        Canvas { ctx, canvasSize in
            let cell = canvasSize.width / CGFloat(n)
            ctx.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(.white))
            for y in 0..<n {
                for x in 0..<n where isOn(x, y) {
                    let r = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                   width: cell, height: cell)
                    ctx.fill(Path(r), with: .color(.black))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Finder patterns plus deterministic filler, so it reads as a QR at a glance.
    private func isOn(_ x: Int, _ y: Int) -> Bool {
        func finder(_ ox: Int, _ oy: Int) -> Bool? {
            let dx = x - ox, dy = y - oy
            guard dx >= 0, dx < 7, dy >= 0, dy < 7 else { return nil }
            let edge = dx == 0 || dx == 6 || dy == 0 || dy == 6
            let core = dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4
            return edge || core
        }
        for (ox, oy) in [(0, 0), (n - 7, 0), (0, n - 7)] {
            if let v = finder(ox, oy) { return v }
        }
        return (x &* 7 &+ y &* 13 &+ x &* y) % 3 == 0
    }
}

#Preview { PaywallView() }