import AppKit

final class MarkdownHighlighter {
    var fontSize: CGFloat {
        didSet {
            guard fontSize != oldValue else { return }
            markdownRules = Self.makeMarkdownRules(fontSize: fontSize, family: fontFamily)
        }
    }

    /// Empty means the system monospaced face. A named family is only used when
    /// it resolves and is fixed-pitch, so an uninstalled font falls back rather
    /// than throwing the editor's alignment out.
    var fontFamily: String = "" {
        didSet {
            guard fontFamily != oldValue else { return }
            markdownRules = Self.makeMarkdownRules(fontSize: fontSize, family: fontFamily)
        }
    }

    var baseFont: NSFont {
        Self.makeBaseFont(fontSize: fontSize, family: fontFamily)
    }

    var boldFont: NSFont {
        Self.makeBoldFont(fontSize: fontSize, family: fontFamily)
    }

    var headerFont: NSFont {
        Self.makeHeaderFont(fontSize: fontSize, family: fontFamily)
    }

    private let baseColor = NSColor.labelColor

    private let codeBlockPattern: NSRegularExpression?
    private let inlineCodePattern: NSRegularExpression?

    private struct HighlightRule {
        let pattern: NSRegularExpression
        let attributes: [NSAttributedString.Key: Any]
    }

    private var markdownRules: [HighlightRule]

    /// Fence markers counted at the last full highlight. nil until one has run,
    /// which forces the first incremental call through the full path.
    private var lastFenceMarkerCount: Int?

    init(fontSize: CGFloat = ZoomState.baseEditorFontSize, fontFamily: String = "") {
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        codeBlockPattern = try? NSRegularExpression(pattern: "^```[\\s\\S]*?^```", options: .anchorsMatchLines)
        inlineCodePattern = try? NSRegularExpression(pattern: "`[^`\n]+`", options: [])
        markdownRules = Self.makeMarkdownRules(fontSize: fontSize, family: fontFamily)
    }

    private static func makeBaseFont(fontSize: CGFloat, family: String) -> NSFont {
        resolved(family: family, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private static func makeBoldFont(fontSize: CGFloat, family: String) -> NSFont {
        guard let base = resolved(family: family, size: fontSize) else {
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        }
        return NSFontManager.shared.convert(base, toHaveTrait: .boldFontMask)
    }

    private static func makeHeaderFont(fontSize: CGFloat, family: String) -> NSFont {
        makeBoldFont(fontSize: fontSize, family: family)
    }

    private static func makeItalicFont(fontSize: CGFloat, family: String) -> NSFont {
        if let base = resolved(family: family, size: fontSize) {
            let italic = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
            // convert() hands back the original when the family has no italic.
            if italic != base { return italic }
        }

        let italicDescriptor = NSFontDescriptor(fontAttributes: [
            .family: "Menlo",
            .face: "Italic"
        ])
        return NSFont(descriptor: italicDescriptor, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// nil for the system face, or when the named family is missing.
    private static func resolved(family: String, size: CGFloat) -> NSFont? {
        guard !family.isEmpty else { return nil }
        return NSFont(name: family, size: size)
    }

    private static func makeMarkdownRules(fontSize: CGFloat, family: String) -> [HighlightRule] {
        var rules: [HighlightRule] = []
        let boldFont = makeBoldFont(fontSize: fontSize, family: family)
        let headerFont = makeHeaderFont(fontSize: fontSize, family: family)
        let italicFont = makeItalicFont(fontSize: fontSize, family: family)

        // Headers
        if let regex = try? NSRegularExpression(pattern: "^#{1,6}\\s.+$", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .font: headerFont,
                .foregroundColor: NSColor.systemBlue
            ]))
        }

        // Bold
        if let regex = try? NSRegularExpression(pattern: "(\\*\\*.+?\\*\\*|__.+?__)", options: []) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .font: boldFont
            ]))
        }

        // Italic
        if let regex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*).+?(?<!\\*)\\*(?!\\*)|(?<!_)_(?!_).+?(?<!_)_(?!_)", options: []) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .font: italicFont
            ]))
        }

        // Links
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)", options: []) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .foregroundColor: NSColor.systemBlue
            ]))
        }

        // Blockquotes
        if let regex = try? NSRegularExpression(pattern: "^>\\s.+$", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }

        // List markers
        if let regex = try? NSRegularExpression(pattern: "^(\\s*[-*+]|\\s*\\d+\\.)\\s", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .foregroundColor: NSColor.systemOrange
            ]))
        }

        // Horizontal rules
        if let regex = try? NSRegularExpression(pattern: "^(-{3,}|\\*{3,}|_{3,})$", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }

        return rules
    }

    func highlight(_ textStorage: NSTextStorage) {
        let text = textStorage.string
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        textStorage.beginEditing()

        // Reset to base attributes
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor
        ], range: fullRange)

        // 1. Find code block ranges to exclude from markdown highlighting
        let fenceRanges = codeBlockRanges(in: text, range: fullRange)
        for range in fenceRanges {
            // Style the entire code block with gray background
            textStorage.addAttributes([
                .backgroundColor: NSColor.quaternaryLabelColor,
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: range)
        }

        let inlineRanges = applyInlineCode(
            to: textStorage,
            text: text,
            in: fullRange,
            skipping: fenceRanges
        )

        let excludedRanges = Self.merged(fenceRanges, inlineRanges)

        // 2. Apply markdown rules only outside code blocks
        applyRules(to: textStorage, text: text, in: fullRange, excluding: excludedRanges)

        textStorage.endEditing()

        lastFenceMarkerCount = Self.fenceMarkerCount(in: nsText)
    }

    func highlight(_ textStorage: NSTextStorage, in editedRange: NSRange) {
        let text = textStorage.string
        let nsText = text as NSString

        guard nsText.length > 0 else { return }

        // Adding or removing a fence marker flips the code/not-code state of
        // every line after it, so only that case needs a full re-highlight.
        // While the marker count holds steady, fence membership outside the
        // edit is stable and the fence ranges recomputed below are enough.
        let fenceMarkerCount = Self.fenceMarkerCount(in: nsText)
        guard fenceMarkerCount == lastFenceMarkerCount else {
            highlight(textStorage)
            return
        }

        let fullRange = NSRange(location: 0, length: nsText.length)
        let allFenceRanges = codeBlockRanges(in: text, range: fullRange)

        let clampedRange = NSIntersectionRange(editedRange, fullRange)
        var range = nsText.paragraphRange(for: clampedRange)
        // An edit inside a fenced block must restyle the whole block, since the
        // block is styled as one unit rather than paragraph by paragraph.
        for fence in allFenceRanges where NSIntersectionRange(fence, range).length > 0 {
            range = NSUnionRange(range, fence)
        }

        textStorage.beginEditing()

        // Reset to base attributes within the edited region
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor
        ], range: range)

        var fenceRanges: [NSRange] = []
        for fence in allFenceRanges {
            let visible = NSIntersectionRange(fence, range)
            guard visible.length > 0 else { continue }
            fenceRanges.append(visible)
            textStorage.addAttributes([
                .backgroundColor: NSColor.quaternaryLabelColor,
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: visible)
        }

        let inlineRanges = applyInlineCode(
            to: textStorage,
            text: text,
            in: range,
            skipping: fenceRanges
        )

        let excludedRanges = Self.merged(fenceRanges, inlineRanges)

        applyRules(to: textStorage, text: text, in: range, excluding: excludedRanges)

        textStorage.endEditing()
    }

    /// Fence ranges intersecting `range`, in ascending order.
    private func codeBlockRanges(in text: String, range: NSRange) -> [NSRange] {
        guard let codeBlockPattern else { return [] }
        return codeBlockPattern.matches(in: text, options: [], range: range).map(\.range)
    }

    /// Styles inline code spans within `range` and returns the styled ranges.
    private func applyInlineCode(
        to textStorage: NSTextStorage,
        text: String,
        in range: NSRange,
        skipping fenceRanges: [NSRange]
    ) -> [NSRange] {
        guard let inlineCodePattern else { return [] }

        var inlineRanges: [NSRange] = []
        inlineCodePattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            guard !Self.hasIntersectingRange(fenceRanges, with: matchRange) else { return }
            inlineRanges.append(matchRange)
            textStorage.addAttributes([
                .backgroundColor: NSColor.quaternaryLabelColor
            ], range: matchRange)
        }
        return inlineRanges
    }

    private func applyRules(
        to textStorage: NSTextStorage,
        text: String,
        in range: NSRange,
        excluding excludedRanges: [NSRange]
    ) {
        for rule in markdownRules {
            rule.pattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                let isInsideCode = Self.hasIntersectingRange(excludedRanges, with: matchRange)
                if !isInsideCode {
                    textStorage.addAttributes(rule.attributes, range: matchRange)
                }
            }
        }
    }

    /// `hasIntersectingRange` binary-searches, so the two ascending sources are
    /// merged into a single ascending array rather than simply concatenated.
    private static func merged(_ fenceRanges: [NSRange], _ inlineRanges: [NSRange]) -> [NSRange] {
        guard !inlineRanges.isEmpty else { return fenceRanges }
        guard !fenceRanges.isEmpty else { return inlineRanges }
        return (fenceRanges + inlineRanges).sorted { $0.location < $1.location }
    }

    private static func fenceMarkerCount(in text: NSString) -> Int {
        var count = 0
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: "```", range: searchRange)
            guard found.location != NSNotFound else { break }
            count += 1
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return count
    }

    private static func hasIntersectingRange(_ sortedRanges: [NSRange], with range: NSRange) -> Bool {
        var low = 0
        var high = sortedRanges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let candidate = sortedRanges[mid]
            if NSIntersectionRange(candidate, range).length > 0 {
                return true
            }
            if candidate.location + candidate.length <= range.location {
                low = mid + 1
            } else if candidate.location >= range.location + range.length {
                high = mid - 1
            } else {
                return true
            }
        }
        return false
    }
}
