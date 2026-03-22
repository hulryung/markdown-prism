import XCTest
@testable import MarkdownPrism

final class ZoomStateTests: XCTestCase {
    func test_zoomIn_increasesScaleByStep() {
        var zoomState = ZoomState(zoomScale: ZoomState.defaultScale)

        zoomState.zoomIn()

        XCTAssertEqual(zoomState.zoomScale, 1.1, accuracy: 0.0001)
    }

    func test_zoomOut_decreasesScaleByStep() {
        var zoomState = ZoomState(zoomScale: ZoomState.defaultScale)

        zoomState.zoomOut()

        XCTAssertEqual(zoomState.zoomScale, 0.9, accuracy: 0.0001)
    }

    func test_reset_returnsScaleToDefault() {
        var zoomState = ZoomState(zoomScale: 1.7)

        zoomState.reset()

        XCTAssertEqual(zoomState.zoomScale, ZoomState.defaultScale, accuracy: 0.0001)
    }

    func test_clampsScaleWithinBounds() {
        var lowZoomState = ZoomState(zoomScale: ZoomState.minScale)
        var highZoomState = ZoomState(zoomScale: ZoomState.maxScale)

        lowZoomState.zoomOut()
        highZoomState.zoomIn()

        XCTAssertEqual(lowZoomState.zoomScale, ZoomState.minScale, accuracy: 0.0001)
        XCTAssertEqual(highZoomState.zoomScale, ZoomState.maxScale, accuracy: 0.0001)
    }
}
