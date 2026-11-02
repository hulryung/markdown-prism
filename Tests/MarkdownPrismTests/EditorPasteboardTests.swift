import AppKit
import XCTest
@testable import MarkdownPrism

/// The editor shows Markdown in a rich-text view so the highlighter can colour
/// it, which must not leak into the pasteboard in either direction (#16, #17).
@MainActor
final class EditorPasteboardTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("MarkdownPrismTests.\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        pasteboard = nil
        super.tearDown()
    }

    private func editor(_ markdown: String) -> EditorView.EditorTextView {
        let textView = EditorView.EditorTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.isRichText = true
        let highlighter = MarkdownHighlighter()
        textView.font = highlighter.baseFont
        textView.string = markdown
        highlighter.highlight(textView.textStorage!)
        return textView
    }

    private func richMarkdown() -> NSAttributedString {
        let rich = NSMutableAttributedString(string: "# Title\n\n**bold** item\n")
        rich.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 24), range: NSRange(location: 0, length: 7))
        rich.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 9, length: 8))
        return rich
    }

    func test_pastingRichAndPlainVersions_insertsThePlainMarkdown() throws {
        let textView = editor("before\n")
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        pasteboard.clearContents()
        pasteboard.writeObjects([richMarkdown()])
        pasteboard.setString("# Title\n\n**bold** item\n", forType: .string)
        XCTAssertTrue(pasteboard.types?.contains(.rtf) ?? false, "the fixture carries a rich version")

        XCTAssertTrue(textView.readSelection(from: pasteboard))

        XCTAssertEqual(textView.string, "before\n# Title\n\n**bold** item\n")
        let pasted = try XCTUnwrap(textView.textStorage?.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
        let existing = try XCTUnwrap(textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(pasted.pointSize, existing.pointSize, "no pasted font size survives")
        XCTAssertNil(textView.textStorage?.attribute(.foregroundColor, at: 16, effectiveRange: nil) as? NSColor == NSColor.red ? true : nil)
    }

    func test_pastingRichTextOnly_insertsItsCharacters() throws {
        let textView = editor("")
        let rich = richMarkdown()
        let rtf = try XCTUnwrap(rich.rtf(from: NSRange(location: 0, length: rich.length), documentAttributes: [:]))
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)
        XCTAssertFalse(pasteboard.types?.contains(.html) ?? true, "the fixture is RTF; the system derives its plain text")

        XCTAssertTrue(textView.readSelection(from: pasteboard, type: .rtf))

        XCTAssertEqual(textView.string, "# Title\n\n**bold** item\n")
    }

    func test_copyingASelection_offersOnlyThePlainString() {
        let markdown = "# Window Management\n\n**Modifiers**\n- **Mega:** Ctrl+Option+Cmd\n"
        let textView = editor(markdown)
        textView.setSelectedRange(NSRange(location: 0, length: (markdown as NSString).length))
        pasteboard.clearContents()

        XCTAssertTrue(textView.writeSelection(to: pasteboard, types: textView.writablePasteboardTypes))

        let types = pasteboard.types ?? []
        XCTAssertTrue(types.contains(.string))
        XCTAssertFalse(types.contains(.rtf), "\(types)")
        XCTAssertFalse(types.contains(.html), "\(types)")
        XCTAssertEqual(pasteboard.string(forType: .string), markdown)
    }
}
