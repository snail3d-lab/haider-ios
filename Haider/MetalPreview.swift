import SwiftUI
import MetalKit

/// Live preview. An MTKView whose drawable the compositor writes into directly:
/// one compute dispatch per frame, then a blit to the drawable. No texture
/// sampling, no render pipeline — the field *is* the framebuffer.
///
/// The view is deliberately bare: no chrome, no overlays. Everything else in the
/// app floats above it as glass.
struct MetalPreview: UIViewRepresentable {

    @ObservedObject var model: HaiderModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: model.compositor?.device)
        view.framebufferOnly = false          // we blit into the drawable
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30    // matches the encode fps
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = context.coordinator
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.model = model
        view.preferredFramesPerSecond = model.fps
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var model: HaiderModel

        init(model: HaiderModel) { self.model = model }

        /// Keep the compositor at exactly the drawable size. Blitting a
        /// 1080x1920 texture into a larger drawable leaves an uninitialised
        /// band, so the canvas follows the view instead of the other way round.
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            guard size.width >= 1, size.height >= 1 else { return }
            model.matchPreview(to: size)
        }

        func draw(in view: MTKView) {
            guard let compositor = model.compositor,
                  let drawable = view.currentDrawable,
                  let queue = compositor.device.makeCommandQueue(),
                  let cmd = queue.makeCommandBuffer() else { return }

            compositor.encode(into: cmd, field: model.field,
                              frame: model.frame, speed: model.speed)

            // Copy the composited frame into the drawable, then present.
            if let src = compositor.outputTexture,
               let blit = cmd.makeBlitCommandEncoder() {
                blit.copy(from: src,
                          sourceSlice: 0, sourceLevel: 0,
                          sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                          sourceSize: MTLSize(width: compositor.outW,
                                              height: compositor.outH, depth: 1),
                          to: drawable.texture,
                          destinationSlice: 0, destinationLevel: 0,
                          destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                blit.endEncoding()
            }
            cmd.present(drawable)
            cmd.commit()
        }
    }
}