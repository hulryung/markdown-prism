import AppKit
import XCTest
@testable import MarkdownPrism

/// Covers the code background following the caret out of an inline span.
///
/// Driven through a real `NSTextView` and `insertText`, because that is what
/// applies typing attributes — replacing characters on the storage directly does
/// not, which is why the highlighter looked innocent when tested on its own.
@MainActor
final class EditorTypingAttributesTests: XCTestCase {
    private let highlighter = MarkdownHighlighter()

    private func editor(_ markdown: String) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = markdown
        highlighter.highlight(textView.textStorage!)
        return textView
    }

    private func background(of textView: NSTextView, at location: Int) -> NSColor? {
        textView.textStorage?.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    /// Types one character with the caret where the reported bug put it: just
    /// past the closing backtick.
    private func typeAfterInlineSpan(
        _ markdown: String,
        clearing: Bool
    ) -> (textView: NSTextView, typedAt: Int) {
        let textView = editor(markdown)
        let afterSpan = (markdown as NSString).range(of: "`code`").upperBound
        textView.setSelectedRange(NSRange(location: afterSpan, length: 0))
        if clearing {
            textView.clearStrayCodeBackground(using: highlighter)
        }
        textView.insertText("X", replacementRange: NSRange(location: afterSpan, length: 0))
        return (textView, afterSpan)
    }

    /// The bug, so the fix below is measured against something real rather than
    /// asserted into existence.
    func test_withoutClearing_typingAfterAnInlineSpanInheritsItsBackground() {
        let (textView, typedAt) = typeAfterInlineSpan("- `code` outside\n", clearing: false)
        XCTAssertNotNil(
            background(of: textView, at: typedAt),
            "the caret inherits from the backtick behind it — this is what was reported"
        )
    }

    func test_typingAfterAnInlineSpan_isNotStyledAsCode() {
        let (textView, typedAt) = typeAfterInlineSpan("- `code` outside\n", clearing: true)
        XCTAssertNil(background(of: textView, at: typedAt))
    }

    /// A styled newline draws as a band across the whole line, which is how the
    /// report looked on screen — and it lands in a paragraph the next highlight
    /// will not revisit, so it never comes back off.
    func test_newlinesTypedAfterAnInlineSpan_areNotStyledAsCode() {
        let markdown = "- `code` outside\n"
        let textView = editor(markdown)
        let afterSpan = (markdown as NSString).range(of: "`code`").upperBound
        textView.setSelectedRange(NSRange(location: afterSpan, length: 0))

        textView.clearStrayCodeBackground(using: highlighter)
        textView.insertText("\n\ntext", replacementRange: NSRange(location: afterSpan, length: 0))

        for offset in 0..<6 {
            XCTAssertNil(
                background(of: textView, at: afterSpan + offset),
                "nothing typed after the span should carry the code background"
            )
        }
    }

    /// Inside a fence the inheritance is what keeps every keystroke from
    /// flashing plain, so it is deliberately left alone.
    func test_typingInsideAFence_keepsTheCodeBackground() {
        let markdown = "before\n\n```swift\nlet x = 1\n```\n"
        let textView = editor(markdown)
        let insideFence = (markdown as NSString).range(of: "let x = 1").upperBound
        textView.setSelectedRange(NSRange(location: insideFence, length: 0))

        textView.clearStrayCodeBackground(using: highlighter)
        textView.insertText("2", replacementRange: NSRange(location: insideFence, length: 0))

        XCTAssertNotNil(background(of: textView, at: insideFence))
    }

    /// Nothing to clear is the common case, and must not disturb the font and
    /// colour the caret inherited for bold or a heading.
    func test_clearing_leavesEverythingElseAlone() {
        let markdown = "**bold** and plain\n"
        let textView = editor(markdown)
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        let before = textView.typingAttributes

        textView.clearStrayCodeBackground(using: highlighter)

        XCTAssertEqual(
            textView.typingAttributes[.font] as? NSFont,
            before[.font] as? NSFont
        )
        XCTAssertEqual(
            textView.typingAttributes[.foregroundColor] as? NSColor,
            before[.foregroundColor] as? NSColor
        )
    }
}
