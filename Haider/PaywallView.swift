import SwiftUI

/// The QR overlay is the premium feature, and its pitch is one sentence: a
/// screenshot of the field shows nothing — except the QR, which still scans. So
/// the code travels even when the words don't.
///
/// Presentation follows the creed: one promise, one price, one button. No
/// feature matrix, no bullets about what you get, no testimonials.
struct PaywallView: View {

    /// Called when the user unlocks, so the caller can flip the premium flag.
    var onUnlock: () -> Void = {}

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
                    // The demo code shown is a real QR, generated on device.
                    onUnlock()
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

/// A real QR, generated on device with the same encoder the clips use.
/// It points at the app's own page, so scanning the demo goes somewhere honest.
struct QRMark: View {
    var url: String = "https://snail3d.com/lab/"
    var size: CGFloat = 168
    var push: Double = 0.95

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { image = Self.render(url: url, push: push) }
        .accessibilityLabel("QR code")
    }

    /// Draw the code, then punch it full of the app's own noise at `push`
    /// strength — the paywall is showing the product, not a clean barcode.
    private static func render(url: String, push: Double) -> UIImage? {
        guard let modules = QRPlane.matrix(for: url) else { return nil }
        let n = modules.count
        let px = 12
        let side = n * px
        var plane = [UInt8](repeating: 0, count: side * side)
        var state: UInt64 = 0x5EED
        func rnd() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 11) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        for my in 0..<n {
            for mx in 0..<n {
                let value: UInt8 = modules[my][mx] ? 2 : 1
                for dy in 0..<px {
                    for dx in 0..<px {
                        if rnd() < push {
                            plane[(my * px + dy) * side + mx * px + dx] = value
                        }
                    }
                }
            }
        }
        let space = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 255, count: side * side)
        for i in 0..<(side * side) where plane[i] == 2 { pixels[i] = 0 }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: side, height: side, bitsPerComponent: 8,
                               bitsPerPixel: 8, bytesPerRow: side, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview { PaywallView() }