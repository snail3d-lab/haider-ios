import Foundation
import Metal
import CoreVideo
import simd

/// GPU compositor for the motion field.
///
/// One compute pass per frame over the whole canvas: each output pixel maps to
/// its dot cell, reads whichever noise population the mask selects, and writes
/// ink or paper. The field and mask are static per edit — only the scroll offset
/// moves — so a frame is one dispatch, roughly a millisecond.
final class MetalCompositor {

    struct Uniforms {
        var outSize: SIMD2<UInt32> = .zero
        var gridSize: SIMD2<UInt32> = .zero
        var dot: UInt32 = 0
        var offset: UInt32 = 0
        var staticBg: UInt32 = 0
        var qrOn: UInt32 = 0
        var ink: SIMD4<Float> = .zero
        var bg: SIMD4<Float> = .zero
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var foreTex: MTLTexture?
    private var backTex: MTLTexture?
    private var maskTex: MTLTexture?
    private var qrTex: MTLTexture?
    private(set) var outputTexture: MTLTexture?

    /// Output canvas. The field grid is derived from this and the dot size.
    private(set) var outW: Int
    private(set) var outH: Int

    var ink: SIMD4<Float> = SIMD4(1, 1, 1, 1)
    var bg: SIMD4<Float> = SIMD4(0.016, 0.020, 0.016, 1)
    var staticBg = false

    /// A QR bias plane at field resolution: 0 = leave the field alone,
    /// 1 = force ink, 2 = force paper. Nil renders the plain field.
    var qrPlane: [UInt8]?

    init?(outW: Int, outH: Int) {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let q = dev.makeCommandQueue(),
              let lib = dev.makeDefaultLibrary(),
              let fn = lib.makeFunction(name: "compose"),
              let state = try? dev.makeComputePipelineState(function: fn) else { return nil }
        self.device = dev
        self.queue = q
        self.pipeline = state
        self.outW = outW
        self.outH = outH
        makeOutput()
    }

    private func makeOutput() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: outW, height: outH, mipmapped: false)
        desc.usage = [.shaderWrite, .shaderRead]
        desc.storageMode = .private
        outputTexture = device.makeTexture(descriptor: desc)
    }

    /// Resize the canvas, e.g. when the user picks a different aspect ratio.
    func resize(outW newW: Int, outH newH: Int) {
        guard newW != outW || newH != outH else { return }
        outW = newW
        outH = newH
        makeOutput()
    }

    /// Upload the two noise populations and the mask. Called once per edit —
    /// the field never changes while a clip renders.
    func upload(field: MotionField) {
        let cols = field.grid.cols
        let rows = field.grid.rows
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint, width: cols, height: rows, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared

        func make(_ bytes: [UInt8]) -> MTLTexture? {
            guard let t = device.makeTexture(descriptor: desc) else { return nil }
            bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                t.replace(region: MTLRegionMake2D(0, 0, cols, rows),
                          mipmapLevel: 0, slice: 0,
                          withBytes: base, bytesPerRow: cols, bytesPerImage: cols * rows)
            }
            return t
        }
        foreTex = make(field.fore)
        backTex = make(field.back)
        maskTex = make(field.mask)
        qrTex = qrPlane.flatMap { make($0) }
    }

    /// Set or clear the QR bias plane. Re-uploads; call after `upload(field:)`
    /// or on its own when only the code changed.
    func setQRPlane(_ plane: [UInt8]?, field: MotionField) {
        qrPlane = plane
        let cols = field.grid.cols
        let rows = field.grid.rows
        guard let plane, plane.count == cols * rows else { qrTex = nil; return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint, width: cols, height: rows, mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        guard let t = device.makeTexture(descriptor: desc) else { return }
        plane.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            t.replace(region: MTLRegionMake2D(0, 0, cols, rows),
                      mipmapLevel: 0, slice: 0,
                      withBytes: base, bytesPerRow: cols, bytesPerImage: cols * rows)
        }
        qrTex = t
    }

    private func uniforms(field: MotionField, frame: Int, speed: Double) -> Uniforms {
        var u = Uniforms()
        u.outSize = SIMD2(UInt32(outW), UInt32(outH))
        u.gridSize = SIMD2(UInt32(field.grid.cols), UInt32(field.grid.rows))
        u.dot = UInt32(field.grid.dot)
        let rows = field.grid.rows
        let offset = Int((Double(frame) * speed).rounded())
        u.offset = UInt32(((offset % rows) + rows) % rows)
        u.staticBg = staticBg ? 1 : 0
        u.qrOn = qrTex != nil ? 1 : 0
        u.ink = ink
        u.bg = bg
        return u
    }

    /// Encode one composited frame into `cmd`. The caller decides when to run it.
    func encode(into cmd: MTLCommandBuffer, field: MotionField, frame: Int, speed: Double) {
        guard let outputTexture, let foreTex, let backTex, let maskTex,
              let enc = cmd.makeComputeCommandEncoder() else { return }
        var u = uniforms(field: field, frame: frame, speed: speed)
        enc.setComputePipelineState(pipeline)
        enc.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.setTexture(foreTex, index: 0)
        enc.setTexture(backTex, index: 1)
        enc.setTexture(maskTex, index: 2)
        enc.setTexture(outputTexture, index: 3)
        // With no plane bound the shader is told qrOn = 0 and never samples it,
        // so a harmless stand-in keeps the binding valid.
        enc.setTexture(qrTex ?? maskTex, index: 4)
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        enc.dispatchThreads(MTLSize(width: outW, height: outH, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        enc.endEncoding()
    }

    /// Synchronous single-frame render, for the encoder's background queue.
    @discardableResult
    func render(field: MotionField, frame: Int, speed: Double) -> MTLTexture? {
        guard let cmd = queue.makeCommandBuffer() else { return nil }
        encode(into: cmd, field: field, frame: frame, speed: speed)
        cmd.commit()
        cmd.waitUntilCompleted()
        return outputTexture
    }
}