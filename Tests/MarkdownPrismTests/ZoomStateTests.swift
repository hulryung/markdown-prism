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

    func test_init_clampsAboveMaxScale() {
        let zoomState = ZoomState(zoomScale: 99)

        XCTAssertEqual(zoomState.zoomScale, ZoomState.maxScale, accuracy: 0.0001)
    }

    func test_init_clampsBelowMinScale() {
        let zoomState = ZoomState(zoomScale: 0.01)

        XCTAssertEqual(zoomState.zoomScale, ZoomState.minScale, accuracy: 0.0001)
    }

    func test_init_roundsToNearestTenth() {
        XCTAssertEqual(ZoomState(zoomScale: 1.234).zoomScale, 1.2, accuracy: 0.0001)
        XCTAssertEqual(ZoomState(zoomScale: 1.05).zoomScale, 1.1, accuracy: 0.0001)
    }

    func test_editorFontSize_scalesWithZoom() {
        let baseFontSize = ZoomState.baseEditorFontSize

        let normalZoomState = ZoomState(zoomScale: 1.0)
        let largeZoomState = ZoomState(zoomScale: 1.5)

        XCTAssertEqual(normalZoomState.editorFontSize, baseFontSize * 1.0)
        XCTAssertEqual(largeZoomState.editorFontSize, baseFontSize * 1.5)
    }

    func test_canZoomIn_isFalseAtMaxScaleAndTrueOneStepBelow() {
        let atMax = ZoomState(zoomScale: ZoomState.maxScale)
        let oneStepBelowMax = ZoomState(zoomScale: ZoomState.maxScale - ZoomState.step)

        XCTAssertFalse(atMax.canZoomIn)
        XCTAssertTrue(oneStepBelowMax.canZoomIn)
    }

    func test_canZoomOut_isFalseAtMinScaleAndTrueOneStepAbove() {
        let atMin = ZoomState(zoomScale: ZoomState.minScale)
        let oneStepAboveMin = ZoomState(zoomScale: ZoomState.minScale + ZoomState.step)

        XCTAssertFalse(atMin.canZoomOut)
        XCTAssertTrue(oneStepAboveMin.canZoomOut)
    }

    func test_repeatedZoomIn_landsExactlyOnMaxScaleWithoutDrift() {
        var zoomState = ZoomState(zoomScale: 1.0)

        for _ in 0..<20 {
            zoomState.zoomIn()
        }

        XCTAssertEqual(zoomState.zoomScale, ZoomState.maxScale)
    }
}
