import SwiftUI

/// The whole interface. The field is the content and it fills the screen; every
/// control floats above it as glass, so nothing competes with what you're making.
///
/// No captions above fields — the placeholder is the label. No decorative icons.
/// No settings screen: the canvas presets and the ink row are the only chrome.
struct ContentView: View {

    @StateObject private var model = HaiderModel()
    @State private var showPaywall = false
    @State private var showQR = false

    var body: some View {
        ZStack {
            Snail.shell.ignoresSafeArea()

            GeometryReader { geo in
                MetalPreview(model: model)
                    .frame(width: fitted(geo.size).width,
                           height: fitted(geo.size).height)
                    // A single hairline, so the field reads as a framed piece
                    // rather than as letterboxing that went wrong.
                    .overlay { Rectangle().strokeBorder(Snail.line, lineWidth: 1) }
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()
                if model.isRendering { rendering } else { composer }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPaywall) {
            PaywallView { model.qrUnlocked = true }
        }
        .sheet(isPresented: $showQR) { qrSheet }
    }

    /// Largest rect of the canvas aspect that fits, so the field is the frame.
    private func fitted(_ available: CGSize) -> CGSize {
        let c = model.canvas.size
        let scale = min(available.width / c.width, available.height / c.height)
        return CGSize(width: (c.width * scale).rounded(),
                      height: (c.height * scale).rounded())
    }

    // MARK: - composer

    private var composer: some View {
        VStack(spacing: 10) {
            if let error = model.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Snail.lime)
                    .padding(.horizontal, 10)
            }

            // The message. Placeholder is the label; no caption above it.
            TextField("Message", text: $model.message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Snail.neutrino)
                .multilineTextAlignment(.center)
                .lineLimit(1...3)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .glassSurface(24)
                .accessibilityLabel("Message to hide")
                .onChange(of: model.message) { _, _ in model.rebuildMask() }

            HStack(spacing: 8) {
                canvasPicker
                Spacer(minLength: 2)
                inks
                Spacer(minLength: 2)
                qrButton
                dice
                saveButton
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .glassSurface(24)
        }
    }

    private var canvasPicker: some View {
        Menu {
            ForEach(HaiderModel.Canvas.allCases) { c in
                Button(c.label) { model.canvas = c }
            }
        } label: {
            Text(model.canvas.label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Snail.neutrino)
                .frame(minWidth: 46, minHeight: 40)
                .glassPill()
        }
        .accessibilityLabel("Output size")
    }

    private var inks: some View {
        HStack(spacing: 6) {
            ForEach(Ink.allCases) { ink in
                Button { model.ink = ink } label: {
                    Circle()
                        .fill(ink.swiftUIColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle().strokeBorder(
                                model.ink == ink ? Snail.lime : ink.swatchRing,
                                lineWidth: model.ink == ink ? 2 : 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ink.label)
            }
        }
    }

    /// The premium's door. The QR is the one thing that survives a screenshot,
    /// so the control sits with the other output choices rather than in a store.
    private var qrButton: some View {
        Button {
            if model.qrUnlocked { withAnimation(.easeInOut(duration: 0.2)) { showQR = true } }
            else { showPaywall = true }
        } label: {
            Image(systemName: "qrcode")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.qrUnlocked ? Snail.lime : Snail.neutrino)
                .frame(width: 40, height: 40)
                .glassPill(tint: Snail.lime, strength: model.qrUnlocked ? 0.22 : 0)
        }
        .accessibilityLabel(model.qrUnlocked ? "QR code" : "QR code, locked")
    }

    /// The URL the clip will carry. One field, no caption — the placeholder is
    /// the label, and the code is visible in the field behind it immediately.
    private var qrSheet: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Snail.dim.opacity(0.5))
                .frame(width: 38, height: 4)
                .padding(.top, 8)

            TextField("Link", text: $model.qrURL)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Snail.neutrino)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .glassSurface(22)
                .accessibilityLabel("Link the QR code opens")

            Button("Done") { showQR = false }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Snail.shell)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Snail.lime, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .presentationDetents([.height(190)])
        .presentationBackground(.clear)
    }

    private var dice: some View {
        Button { model.reseed() } label: {
            Image(systemName: "dice")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Snail.neutrino)
                .frame(width: 40, height: 40)
                .glassPill()
        }
        .accessibilityLabel("New noise")
    }

    private var saveButton: some View {
        Button { model.save() } label: {
            Group {
                if model.savedURL != nil {
                    Image(systemName: "checkmark")
                } else {
                    Text("Save")
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(model.savedURL != nil ? Snail.shell : Snail.shell)
            .frame(minWidth: 62, minHeight: 40)
            .glassPill(tint: Snail.lime, strength: 0.95)
        }
        .accessibilityLabel(model.savedURL != nil ? "Saved" : "Save clip")
    }

    // MARK: - rendering

    private var rendering: some View {
        VStack(spacing: 10) {
            Text("\(Int(model.progress * 100))%")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Snail.neutrino)
            ProgressView(value: model.progress)
                .tint(Snail.lime)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassSurface(26)
        .accessibilityLabel("Rendering clip")
    }
}

#Preview { ContentView() }