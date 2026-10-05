import Foundation
import AVFoundation
import CoreVideo
import Metal

/// Renders the motion field to an MP4 in the app's Documents directory.
///
/// Mirrors the desktop codec: the field is static, only the scroll offset moves,
/// so each frame is one GPU dispatch plus a H.264 encode. A 40-second 1080x1920
/// clip takes a few seconds on A-series silicon.
final class ClipWriter: ObservableObject, @unchecked Sendable {

    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var outputURL: URL?
    @Published var error: String?

    private let compositor: MetalCompositor
    private let workQueue = DispatchQueue(label: "haider.encode", qos: .userInitiated)
    private let lock = NSLock()
    private var _cancelled = false
    private var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); defer { lock.unlock() }; _cancelled = newValue }
    }

    init(compositor: MetalCompositor) {
        self.compositor = compositor
    }

    func cancel() {
        cancelled = true
        DispatchQueue.main.async { self.isRunning = false }
    }

    struct Options {
        var seconds: Double = 8
        var fps: Int = 30
        var speed: Double = 2.0
        var fileStem = "haider"
    }

    func write(field: MotionField, options: Options) {
        guard !isRunning else { return }
        error = nil
        outputURL = nil
        progress = 0
        isRunning = true
        cancelled = false

        workQueue.async { [weak self] in
            guard let self else { return }
            self.run(field: field, options: options)
        }
    }

    private func run(field: MotionField, options: Options) {
        let totalFrames = max(1, Int(options.seconds * Double(options.fps)))
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                "\(options.fileStem)_\(Int(Date().timeIntervalSince1970)).mp4")

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: compositor.outW,
                AVVideoHeightKey: compositor.outH,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ],
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw EncodeError.setup }
            writer.add(input)

            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: compositor.outW,
                kCVPixelBufferHeightKey as String: compositor.outH,
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input, sourcePixelBufferAttributes: attrs)

            guard writer.startWriting() else { throw EncodeError.setup }
            writer.startSession(atSourceTime: .zero)

            // Metal writes in its own colour space; the buffer is BGRA.
            var pool: CVPixelBufferPool?
            if let adaptorPool = adaptor.pixelBufferPool { pool = adaptorPool }

            for frame in 0..<totalFrames {
                if cancelled { break }
                while !input.isReadyForMoreMediaData && !cancelled {
                    Thread.sleep(forTimeInterval: 0.004)
                }
                if cancelled { break }

                guard let texture = compositor.render(field: field, frame: frame,
                                                      speed: options.speed),
                      let buffer = makeBuffer(pool: pool) else { continue }

                copy(texture: texture, into: buffer)
                let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(options.fps))
                adaptor.append(buffer, withPresentationTime: time)

                if frame % 5 == 0 {
                    let p = Double(frame) / Double(totalFrames)
                    DispatchQueue.main.async { self.progress = p }
                }
            }

            input.markAsFinished()
            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            done.wait()

            DispatchQueue.main.async {
                self.isRunning = false
                if writer.status == .completed {
                    self.progress = 1
                    self.outputURL = url
                } else {
                    self.error = writer.error?.localizedDescription ?? "Encode failed"
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.isRunning = false
                self.error = error.localizedDescription
            }
        }
    }

    private func makeBuffer(pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        if let pool {
            var pb: CVPixelBuffer?
            if CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess {
                return pb
            }
        }
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, compositor.outW, compositor.outH,
                                         kCVPixelFormatType_32BGRA, nil, &pb)
        return status == kCVReturnSuccess ? pb : nil
    }

    /// Pull the composited frame back off the GPU into a pixel buffer.
    private func copy(texture: MTLTexture, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let cmd = compositor.device.makeCommandQueue()?.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let byteCount = bytesPerRow * compositor.outH
        let size = MTLSize(width: compositor.outW, height: compositor.outH, depth: 1)
        let origin = MTLOrigin(x: 0, y: 0, z: 0)
        guard let dst = compositor.device.makeBuffer(bytesNoCopy: base,
                                                     length: byteCount,
                                                     options: .storageModeShared,
                                                     deallocator: nil) else { return }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: origin, sourceSize: size, to: dst,
                  destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: byteCount)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    enum EncodeError: LocalizedError {
        case setup
        var errorDescription: String? { "Could not start the encoder." }
    }
}