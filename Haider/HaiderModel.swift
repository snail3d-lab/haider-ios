import SwiftUI
import Photos

/// The app's state: one field, one message, one clip. All the depth lives here;
/// the screen stays three controls.
@MainActor
final class HaiderModel: ObservableObject {

    /// Output presets. People put these in different places, so the canvas is a
    /// choice rather than a constant. Grid = canvas / dot, so changing preset
    /// rebuilds the field at the new shape.
    enum Canvas: String, CaseIterable, Identifiable {
        case portrait, square, landscape, tall

        var id: String { rawValue }

        var label: String {
            switch self {
            case .portrait: "9:16"
            case .tall: "4:5"
            case .square: "1:1"
            case .landscape: "16:9"
            }
        }

        var size: CGSize {
            switch self {
            case .portrait: CGSize(width: 1080, height: 1920)
            case .tall: CGSize(width: 1080, height: 1350)
            case .square: CGSize(width: 1080, height: 1080)
            case .landscape: CGSize(width: 1920, height: 1080)
            }
        }
    }

    static let dot = 5

    @Published var message: String = "HIDE FROM\nTHE AI" {
        didSet { if message != oldValue { markDirty() } }
    }
    @Published var ink: Ink = .white {
        didSet { applyInk() }
    }
    @Published var canvas: Canvas = .portrait {
        didSet { rebuildField() }
    }
    @Published var progress: Double = 0
    @Published var isRendering = false
    @Published var savedURL: URL?
    @Published var error: String?

    /// Playback position, advanced by the preview's own display link.
    @Published var frame: Int = 0

    let compositor: MetalCompositor?
    private let writer: ClipWriter?
    private(set) var field: MotionField
    private var seed: UInt64 = 7

    /// Readable playback. The desktop tool calls this `--speed 2`; slower reads
    /// as drift, faster as a strobe.
    let speed: Double = 2.0
    let fps: Int = 30

    init() {
        let size = Canvas.portrait.size
        let grid = MotionField.Grid(cols: Int(size.width) / Self.dot,
                                    rows: Int(size.height) / Self.dot,
                                    dot: Self.dot)
        field = MotionField(grid: grid, speckle: 4, density: 0.5, seed: 7)
        compositor = MetalCompositor(outW: Int(size.width), outH: Int(size.height))
        if let compositor {
            writer = ClipWriter(compositor: compositor)
        } else {
            writer = nil
        }
        applyInk()
        field.setText(message)
        compositor?.upload(field: field)
    }

    // MARK: - edits

    func rebuildMask() {
        field.setText(message)
        compositor?.upload(field: field)
        markDirty()
    }

    func reseed() {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        field.reseed(seed)
        compositor?.upload(field: field)
        markDirty()
    }

    /// Called by the preview when the drawable size changes. The grid follows
    /// the drawable so the field fills it exactly; because the view is locked to
    /// the canvas aspect, the result looks identical to the export.
    func matchPreview(to size: CGSize) {
        guard !isRendering else { return }
        let w = Int(size.width), h = Int(size.height)
        guard w / Self.dot != field.grid.cols || h / Self.dot != field.grid.rows else { return }
        compositor?.resize(outW: w, outH: h)
        rebuildGrid(cols: w / Self.dot, rows: h / Self.dot)
    }

    /// Resize the compositor to the true output canvas for an export, so the
    /// saved file is the chosen size rather than the preview's.
    private func useExportSize() {
        let c = canvas.size
        compositor?.resize(outW: Int(c.width), outH: Int(c.height))
        rebuildGrid(cols: Int(c.width) / Self.dot, rows: Int(c.height) / Self.dot)
    }

    private func rebuildGrid(cols: Int, rows: Int) {
        guard cols > 8, rows > 8 else { return }
        field = MotionField(grid: .init(cols: cols, rows: rows, dot: Self.dot),
                            speckle: field.speckle, density: field.density, seed: seed)
        field.setText(message)
        compositor?.upload(field: field)
    }

    private func rebuildField() {
        let size = canvas.size
        let grid = MotionField.Grid(cols: Int(size.width) / Self.dot,
                                    rows: Int(size.height) / Self.dot,
                                    dot: Self.dot)
        field = MotionField(grid: grid, speckle: field.speckle,
                            density: field.density, seed: seed)
        compositor?.resize(outW: Int(size.width), outH: Int(size.height))
        field.setText(message)
        compositor?.upload(field: field)
        markDirty()
    }

    private func applyInk() {
        compositor?.ink = ink.linear
        compositor?.bg = ink.background
    }

    private func markDirty() { savedURL = nil }

    // MARK: - export

    func save() {
        guard let writer else {
            error = "Metal is unavailable on this device."
            return
        }
        error = nil
        savedURL = nil
        isRendering = true
        progress = 0
        useExportSize()

        var options = ClipWriter.Options()
        options.seconds = 8
        options.fps = fps
        options.speed = speed
        writer.write(field: field, options: options)

        Task {
            while writer.isRunning {
                progress = writer.progress
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            isRendering = false
            progress = writer.progress
            if let url = writer.outputURL {
                await saveToPhotos(url)
            } else {
                error = writer.error
            }
        }
    }

    private func saveToPhotos(_ url: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = "Photo access is off."
            savedURL = url
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            savedURL = url
        } catch {
            self.error = error.localizedDescription
        }
    }
}
