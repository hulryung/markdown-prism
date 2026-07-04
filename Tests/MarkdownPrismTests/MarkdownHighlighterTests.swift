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

    func test_highlight_headerInsideFencedBlock_keepsCodeBlockStyling() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "```\n# Title\n```"
        let textStorage = NSTextStorage(string: markdown)

        highlighter.highlight(textStorage)

        let headerLineIndex = markdown.utf16Distance(of: "# Title")
        let attributes = textStorage.attributes(at: headerLineIndex, effectiveRange: nil)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        let foreground = try XCTUnwrap(attributes[.foregroundColor] as? NSColor)
        let background = try XCTUnwrap(attributes[.backgroundColor] as? NSColor)

        XCTAssertEqual(foreground, .secondaryLabelColor)
        XCTAssertEqual(background, .quaternaryLabelColor)
        XCTAssertFalse(font.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertNotEqual(foreground, .systemBlue)
    }

    func test_highlight_inlineCodeOutsideFence_getsBackground() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "Use `code` here"
        let textStorage = NSTextStorage(string: markdown)

        highlighter.highlight(textStorage)

        let codeIndex = markdown.utf16Distance(of: "`code`") + 1
        let attributes = textStorage.attributes(at: codeIndex, effectiveRange: nil)
        let background = try XCTUnwrap(attributes[.backgroundColor] as? NSColor)

        XCTAssertEqual(background, .quaternaryLabelColor)
    }

    func test_highlight_inlineBacktickInsideFence_isNotDoubleStyled() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "```\nsome `code` here\n```"
        let textStorage = NSTextStorage(string: markdown)

        highlighter.highlight(textStorage)

        let insideFenceIndex = markdown.utf16Distance(of: "`code`") + 1
        let attributes = textStorage.attributes(at: insideFenceIndex, effectiveRange: nil)
        let foreground = try XCTUnwrap(attributes[.foregroundColor] as? NSColor)
        let background = try XCTUnwrap(attributes[.backgroundColor] as? NSColor)

        XCTAssertEqual(foreground, .secondaryLabelColor)
        XCTAssertEqual(background, .quaternaryLabelColor)
    }

    func test_highlight_appliesRuleStylingForBoldLinkListAndQuote() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "**bold**\n[t](u)\n- item\n> q"
        let textStorage = NSTextStorage(string: markdown)

        highlighter.highlight(textStorage)

        let boldIndex = markdown.utf16Distance(of: "**bold**") + 2
        let boldFont = try XCTUnwrap(textStorage.attributes(at: boldIndex, effectiveRange: nil)[.font] as? NSFont)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))

        let linkIndex = markdown.utf16Distance(of: "[t](u)") + 1
        let linkColor = try XCTUnwrap(textStorage.attributes(at: linkIndex, effectiveRange: nil)[.foregroundColor] as? NSColor)
        XCTAssertEqual(linkColor, .systemBlue)

        let listIndex = markdown.utf16Distance(of: "- item")
        let listColor = try XCTUnwrap(textStorage.attributes(at: listIndex, effectiveRange: nil)[.foregroundColor] as? NSColor)
        XCTAssertEqual(listColor, .systemOrange)

        let quoteIndex = markdown.utf16Distance(of: "> q")
        let quoteColor = try XCTUnwrap(textStorage.attributes(at: quoteIndex, effectiveRange: nil)[.foregroundColor] as? NSColor)
        XCTAssertEqual(quoteColor, .secondaryLabelColor)
    }

    func test_highlight_emptyString_doesNotCrash() {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let textStorage = NSTextStorage(string: "")

        highlighter.highlight(textStorage)

        XCTAssertEqual(textStorage.length, 0)
    }

    func test_highlight_multiUTF16UnitCharacters_appliesAttributesAtCorrectIndices() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "# 제목 😀\n**굵게**"
        let textStorage = NSTextStorage(string: markdown)

        highlighter.highlight(textStorage)

        let headerColor = try XCTUnwrap(textStorage.attributes(at: 0, effectiveRange: nil)[.foregroundColor] as? NSColor)
        XCTAssertEqual(headerColor, .systemBlue)

        let boldIndex = markdown.utf16Distance(of: "**굵게**") + 2
        let boldFont = try XCTUnwrap(textStorage.attributes(at: boldIndex, effectiveRange: nil)[.font] as? NSFont)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func test_highlightInRange_stylesEditedParagraphInPlainDocument() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "plain line\n**bold**\nanother line"
        let textStorage = NSTextStorage(string: markdown)
        highlighter.highlight(textStorage)

        let boldRange = (markdown as NSString).range(of: "**bold**")
        highlighter.highlight(textStorage, in: boldRange)

        let boldIndex = boldRange.location + 2
        let boldFont = try XCTUnwrap(textStorage.attributes(at: boldIndex, effectiveRange: nil)[.font] as? NSFont)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
    }
}

private extension String {
    /// UTF-16 offset of the start of the first occurrence of `substring`.
    func utf16Distance(of substring: String) -> Int {
        (self as NSString).range(of: substring).location
    }
}
