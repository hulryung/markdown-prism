import AppKit

/// Draws the editor's line number gutter.
///
/// The numbers are painted into the text view's own background rather than an
/// `NSRulerView`: installing a ruler on the scroll view blanks the text out
/// entirely, and drawing here keeps everything in one coordinate space — line
/// fragment rects need only the container inset applied.
///
/// Numbers are drawn once per logical line, against the first visual row, so a
/// wrapped line is not numbered twice.
struct LineNumberGutter {
    /// Space between the numbers and the text, and the left window edge.
    static let padding: CGFloat = 8
    private static let minimumWidth: CGFloat = 22

    var lineIndex = LineIndex("")
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// How much room the numbers need, which the text container is inset by.
    var width: CGFloat {
        let digits = max(2, String(lineIndex.lineCount).count)
        let sample = String(repeating: "8", count: digits)
        let textWidth = (sample as NSString).size(withAttributes: [.font: font]).width
        return max(Self.minimumWidth, textWidth.rounded(.up)) + Self.padding * 2
    }

    func draw(
        in dirtyRect: NSRect,
        layoutManager: NSLayoutManager,
        container: NSTextContainer,
        containerInset: NSSize,
        bounds: NSRect
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // Only the fragments that intersect the dirty area need numbering.
        let glyphs = layoutManager.glyphRange(
            forBoundingRect: dirtyRect.offsetBy(dx: 0, dy: -containerInset.height),
            in: container
        )

        var glyphIndex = glyphs.location
        var lastLine = -1

        while glyphIndex < NSMaxRange(glyphs) {
            var fragmentRange = NSRange(location: 0, length: 0)
            let fragment = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &fragmentRange
            )

            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentRange.location)
            let line = lineIndex.line(forOffset: characterIndex)
            if line != lastLine {
                lastLine = line
                drawNumber(line + 1, in: fragment, inset: containerInset, attributes: attributes)
            }

            guard fragmentRange.length > 0 else { break }
            glyphIndex = NSMaxRange(fragmentRange)
        }

        // An empty trailing line has no glyphs, so it never appears above.
        let extra = layoutManager.extraLineFragmentRect
        if extra.height > 0, lineIndex.lineCount - 1 != lastLine {
            drawNumber(lineIndex.lineCount, in: extra, inset: containerInset, attributes: attributes)
        }
    }

    private func drawNumber(
        _ number: Int,
        in fragment: NSRect,
        inset: NSSize,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let label = String(number) as NSString
        let size = label.size(withAttributes: attributes)
        // Right-aligned against the text, and vertically centred on the line.
        let x = width - Self.padding - size.width
        let y = fragment.minY + inset.height + ((fragment.height - size.height) / 2).rounded()
        label.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }
}
