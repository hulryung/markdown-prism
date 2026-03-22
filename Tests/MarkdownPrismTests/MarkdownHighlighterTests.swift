import AppKit
import XCTest
@testable import MarkdownPrism

final class MarkdownHighlighterTests: XCTestCase {
    func test_fonts_reflectConfiguredFontSize() {
        let highlighter = MarkdownHighlighter(fontSize: 18)

        XCTAssertEqual(highlighter.baseFont.pointSize, 18, accuracy: 0.001)
        XCTAssertEqual(highlighter.boldFont.pointSize, 18, accuracy: 0.001)
        XCTAssertEqual(highlighter.headerFont.pointSize, 18, accuracy: 0.001)
    }

    func test_highlight_preservesHeaderRuleAtDifferentFontSize() throws {
        let highlighter = MarkdownHighlighter(fontSize: 20)
        let textStorage = NSTextStorage(string: "# Heading")

        highlighter.highlight(textStorage)

        let attributes = textStorage.attributes(at: 0, effectiveRange: nil)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        let color = try XCTUnwrap(attributes[.foregroundColor] as? NSColor)

        XCTAssertEqual(font.pointSize, 20, accuracy: 0.001)
        XCTAssertEqual(color, .systemBlue)
    }
}
