import AppKit
import XCTest
@testable import MarkdownPrism

final class LineIndexTests: XCTestCase {
    func test_lineCount_countsTrailingNewlineAsAnOpenLine() {
        XCTAssertEqual(LineIndex("").lineCount, 1)
        XCTAssertEqual(LineIndex("one").lineCount, 1)
        XCTAssertEqual(LineIndex("one\ntwo").lineCount, 2)
        XCTAssertEqual(LineIndex("one\n").lineCount, 2)
    }

    func test_lineForOffset_mapsEveryOffsetToItsLine() {
        let text = "abc\nde\n\nf"
        let index = LineIndex(text)

        XCTAssertEqual(index.line(forOffset: 0), 0)
        XCTAssertEqual(index.line(forOffset: 3), 0)  // the newline itself
        XCTAssertEqual(index.line(forOffset: 4), 1)
        XCTAssertEqual(index.line(forOffset: 6), 1)
        XCTAssertEqual(index.line(forOffset: 7), 2)  // empty line
        XCTAssertEqual(index.line(forOffset: 8), 3)
    }

    func test_offsetForLine_clampsOutOfRangeLines() {
        let index = LineIndex("abc\nde")

        XCTAssertEqual(index.offset(forLine: 0), 0)
        XCTAssertEqual(index.offset(forLine: 1), 4)
        XCTAssertEqual(index.offset(forLine: -5), 0)
        XCTAssertEqual(index.offset(forLine: 99), 4)
    }

    func test_offsets_countUTF16UnitsSoEmojiAndHangulStayAligned() {
        let text = "# 제목 😀\n**굵게**"
        let index = LineIndex(text)
        let secondLine = (text as NSString).range(of: "**굵게**").location

        XCTAssertEqual(index.offset(forLine: 1), secondLine)
        XCTAssertEqual(index.line(forOffset: secondLine), 1)
    }

    func test_roundTrip_lineToOffsetAndBack() {
        let index = LineIndex("a\nbb\n\nccc\n")
        for line in 0..<index.lineCount {
            XCTAssertEqual(index.line(forOffset: index.offset(forLine: line)), line)
        }
    }
}

final class ScrollSyncArbiterTests: XCTestCase {
    func test_firstScrollFromEitherPane_propagates() {
        var arbiter = ScrollSyncArbiter()
        XCTAssertTrue(arbiter.shouldPropagate(from: .preview, at: 0))
    }

    func test_theOtherPaneIsIgnoredWhileTheOwnerIsActive() {
        var arbiter = ScrollSyncArbiter()

        XCTAssertTrue(arbiter.shouldPropagate(from: .editor, at: 0))
        // The preview scrolling because the editor just drove it must not
        // bounce back and fight the editor.
        XCTAssertFalse(arbiter.shouldPropagate(from: .preview, at: 0.05))
        XCTAssertTrue(arbiter.shouldPropagate(from: .editor, at: 0.1))
    }

    func test_theOtherPaneTakesOverOnceTheOwnerGoesQuiet() {
        var arbiter = ScrollSyncArbiter()

        XCTAssertTrue(arbiter.shouldPropagate(from: .editor, at: 0))
        XCTAssertFalse(arbiter.shouldPropagate(from: .preview, at: 0.1))

        let afterLockout = ScrollSyncArbiter.lockout + 0.01
        XCTAssertTrue(arbiter.shouldPropagate(from: .preview, at: afterLockout))
        XCTAssertFalse(arbiter.shouldPropagate(from: .editor, at: afterLockout + 0.01))
    }

    func test_lockoutRunsFromTheLastEventNotTheFirst() {
        var arbiter = ScrollSyncArbiter()

        // A continuous editor drag keeps renewing ownership.
        var time = 0.0
        while time < ScrollSyncArbiter.lockout * 3 {
            XCTAssertTrue(arbiter.shouldPropagate(from: .editor, at: time))
            time += 0.05
        }
        XCTAssertFalse(arbiter.shouldPropagate(from: .preview, at: time))
    }
}

final class ScrollSyncBusTests: XCTestCase {
    func test_editorScroll_drivesPreview() {
        let bus = ScrollSyncBus()
        var previewLine: Int?
        bus.scrollPreview = { previewLine = $0 }

        bus.editorDidScroll(toLine: 42)

        XCTAssertEqual(previewLine, 42)
    }

    func test_disabledBus_doesNotForwardScrolls() {
        let bus = ScrollSyncBus()
        var called = false
        bus.scrollPreview = { _ in called = true }
        bus.scrollEditor = { _ in called = true }
        bus.isEnabled = false

        bus.editorDidScroll(toLine: 1)
        bus.previewDidScroll(toLine: 1)

        XCTAssertFalse(called)
    }

    func test_previewEchoOfAnEditorScroll_doesNotReachTheEditor() {
        let bus = ScrollSyncBus()
        var editorLine: Int?
        bus.scrollPreview = { _ in }
        bus.scrollEditor = { editorLine = $0 }

        bus.editorDidScroll(toLine: 10)
        bus.previewDidScroll(toLine: 10)

        XCTAssertNil(editorLine)
    }
}

final class LineNumberGutterTests: XCTestCase {
    func test_width_reservesRoomForTwoDigitsEvenInAShortDocument() {
        var gutter = LineNumberGutter()
        gutter.lineIndex = LineIndex("one\ntwo\n")

        let twoDigits = gutter.width
        gutter.lineIndex = LineIndex("only one line")

        XCTAssertEqual(gutter.width, twoDigits, "the gutter should not twitch on short files")
    }

    func test_width_growsWithTheLineCount() throws {
        var gutter = LineNumberGutter()
        var widths: [CGFloat] = []
        for lines in [90, 900, 9_000, 90_000] {
            gutter.lineIndex = LineIndex(String(repeating: "x\n", count: lines))
            widths.append(gutter.width)
        }

        // Never shrinks as the document grows...
        for (previous, next) in zip(widths, widths.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next, previous)
        }
        // ...and does grow once the numbers outrun the minimum width, which is
        // wide enough that crossing 99 lines does not shift the text sideways.
        XCTAssertGreaterThan(try XCTUnwrap(widths.last), try XCTUnwrap(widths.first))
    }

    func test_width_tracksTheFontSize() {
        var small = LineNumberGutter()
        small.lineIndex = LineIndex(String(repeating: "x\n", count: 500))
        var large = small
        large.font = .monospacedDigitSystemFont(ofSize: 24, weight: .regular)

        XCTAssertGreaterThan(large.width, small.width)
    }
}
