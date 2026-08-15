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

    func test_highlightInRange_documentWithFence_stylesEditedParagraphIncrementally() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "**bold**\n```\n# fenced\n```\ntail"
        let textStorage = NSTextStorage(string: markdown)
        highlighter.highlight(textStorage)

        let boldRange = (markdown as NSString).range(of: "**bold**")
        highlighter.highlight(textStorage, in: boldRange)

        let boldFont = try XCTUnwrap(
            textStorage.attributes(at: boldRange.location + 2, effectiveRange: nil)[.font] as? NSFont
        )
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))

        // The untouched fence keeps its code styling instead of being reset.
        let fencedIndex = markdown.utf16Distance(of: "# fenced")
        let fencedAttributes = textStorage.attributes(at: fencedIndex, effectiveRange: nil)
        XCTAssertEqual(fencedAttributes[.foregroundColor] as? NSColor, .secondaryLabelColor)
        XCTAssertEqual(fencedAttributes[.backgroundColor] as? NSColor, .quaternaryLabelColor)
    }

    func test_highlightInRange_editInsideFence_restylesWholeBlock() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "intro\n```\n# one\n# two\n```\ntail"
        let textStorage = NSTextStorage(string: markdown)
        highlighter.highlight(textStorage)

        let editedLine = (markdown as NSString).range(of: "# one")
        highlighter.highlight(textStorage, in: editedLine)

        for line in ["# one", "# two"] {
            let attributes = textStorage.attributes(at: markdown.utf16Distance(of: line), effectiveRange: nil)
            XCTAssertEqual(attributes[.foregroundColor] as? NSColor, .secondaryLabelColor, line)
            XCTAssertEqual(attributes[.backgroundColor] as? NSColor, .quaternaryLabelColor, line)
        }
    }

    func test_highlightInRange_afterFenceMarkerAdded_fallsBackToFullHighlight() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let textStorage = NSTextStorage(string: "# heading\ntail")
        highlighter.highlight(textStorage)

        // Typing a fence pair flips the heading into code, which only a full
        // re-highlight can pick up.
        let updated = "```\n# heading\n```\ntail"
        textStorage.replaceCharacters(
            in: NSRange(location: 0, length: textStorage.length),
            with: updated
        )
        let tailRange = (updated as NSString).range(of: "tail")
        highlighter.highlight(textStorage, in: tailRange)

        let attributes = textStorage.attributes(at: updated.utf16Distance(of: "# heading"), effectiveRange: nil)
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, .secondaryLabelColor)
        XCTAssertEqual(attributes[.backgroundColor] as? NSColor, .quaternaryLabelColor)
    }

    func test_highlightInRange_inlineCodeOutsideFence_keepsRulesOff() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let markdown = "```\nfence\n```\nuse `**not bold**` here"
        let textStorage = NSTextStorage(string: markdown)
        highlighter.highlight(textStorage)

        let editedLine = (markdown as NSString).range(of: "use `**not bold**` here")
        highlighter.highlight(textStorage, in: editedLine)

        let insideBackticks = markdown.utf16Distance(of: "**not bold**") + 2
        let attributes = textStorage.attributes(at: insideBackticks, effectiveRange: nil)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        XCTAssertEqual(attributes[.backgroundColor] as? NSColor, .quaternaryLabelColor)
        XCTAssertFalse(font.fontDescriptor.symbolicTraits.contains(.bold))
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

    // MARK: - Where the caret may keep a code background

    /// An inline span ends on a backtick, so the caret after one inherits a
    /// background belonging to the character behind it — and hands it to
    /// everything typed next, newlines included.
    func test_isInsideCodeBlock_isFalseAfterAnInlineSpan() {
        let text = "- `code` outside\n\ntext\n"
        let highlighter = MarkdownHighlighter()

        let afterClosingBacktick = (text as NSString).range(of: "`code`").upperBound
        XCTAssertFalse(highlighter.isInsideCodeBlock(text, at: afterClosingBacktick))
        XCTAssertFalse(highlighter.isInsideCodeBlock(text, at: (text as NSString).length))
    }

    /// Inside a fence the inheritance is right: the block continues, and
    /// clearing it would flash every keystroke plain until the re-highlight.
    func test_isInsideCodeBlock_isTrueWithinAFence() {
        let text = "before\n\n```swift\nlet x = 1\n```\n\nafter\n"
        let highlighter = MarkdownHighlighter()

        let inside = (text as NSString).range(of: "let x = 1").location + 3
        XCTAssertTrue(highlighter.isInsideCodeBlock(text, at: inside))
    }

    func test_isInsideCodeBlock_isFalseOutsideAnyCode() {
        let text = "before\n\n```\nfenced\n```\n\nafter\n"
        let highlighter = MarkdownHighlighter()

        XCTAssertFalse(highlighter.isInsideCodeBlock(text, at: 2))
        XCTAssertFalse(highlighter.isInsideCodeBlock(text, at: (text as NSString).range(of: "after").location))
    }

    func test_isInsideCodeBlock_handlesAnEmptyDocument() {
        XCTAssertFalse(MarkdownHighlighter().isInsideCodeBlock("", at: 0))
    }
}
