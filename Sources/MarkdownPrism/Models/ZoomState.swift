import CoreGraphics

struct ZoomState {
    static let defaultScale = 1.0
    static let step = 0.1
    static let minScale = 0.5
    static let maxScale = 3.0
    static let baseEditorFontSize: CGFloat = 14

    private(set) var zoomScale: Double

    init(zoomScale: Double) {
        self.zoomScale = Self.clamp(zoomScale)
    }

    var editorFontSize: CGFloat {
        Self.baseEditorFontSize * zoomScale
    }

    var canZoomIn: Bool {
        zoomScale < Self.maxScale
    }

    var canZoomOut: Bool {
        zoomScale > Self.minScale
    }

    mutating func zoomIn() {
        zoomScale = Self.clamp(zoomScale + Self.step)
    }

    mutating func zoomOut() {
        zoomScale = Self.clamp(zoomScale - Self.step)
    }

    mutating func reset() {
        zoomScale = Self.defaultScale
    }

    static func clamp(_ scale: Double) -> Double {
        min(max(rounded(scale), minScale), maxScale)
    }

    private static func rounded(_ scale: Double) -> Double {
        (scale * 10).rounded() / 10
    }
}
