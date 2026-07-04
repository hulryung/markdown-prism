import AppKit

final class MarkdownHighlighter {
    var fontSize: CGFloat {
        didSet {
            markdownRules = Self.makeMarkdownRules(fontSize: fontSize)
        }
    }

    var baseFont: NSFont {
        Self.makeBaseFont(fontSize: fontSize)
    }

    var boldFont: NSFont {
        Self.makeBoldFont(fontSize: fontSize)
    }

    var headerFont: NSFont {
        Self.makeHeaderFont(fontSize: fontSize)
    }

    private let baseColor = NSColor.labelColor

    private let codeBlockPattern: NSRegularExpression?
    private let inlineCodePattern: NSRegularExpression?

    private struct HighlightRule {
        let pattern: NSRegularExpression
        let attributes: [NSAttributedString.Key: Any]
    }

    private var markdownRules: [HighlightRule]

    init(fontSize: CGFloat = ZoomState.baseEditorFontSize) {
        self.fontSize = fontSize
        codeBlockPattern = try? NSRegularExpression(pattern: "^```[\\s\\S]*?^```", options: .anchorsMatchLines)
        inlineCodePattern = try? NSRegularExpression(pattern: "`[^`\n]+`", options: [])
        markdownRules = Self.makeMarkdownRules(fontSize: fontSize)
    }

    private static func makeBaseFont(fontSize: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private static func makeBoldFont(fontSize: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    }

    private static func makeHeaderFont(fontSize: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    }

    private static func makeItalicFont(fontSize: CGFloat) -> NSFont {
        let italicDescriptor = NSFontDescriptor(fontAttributes: [
            .family: "Menlo",
            .face: "Italic"
        ])

        return NSFont(descriptor: italicDescriptor, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private static func makeMarkdownRules(fontSize: CGFloat) -> [HighlightRule] {
        var rules: [HighlightRule] = []
        let boldFont = makeBoldFont(fontSize: fontSize)
        let headerFont = makeHeaderFont(fontSize: fontSize)
        let italicFont = makeItalicFont(fontSize: fontSize)

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
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        textStorage.beginEditing()

        // Reset to base attributes
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor
        ], range: fullRange)

        // 1. Find code block ranges to exclude from markdown highlighting
        var excludedRanges: [NSRange] = []

        codeBlockPattern?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            excludedRanges.append(range)
            // Style the entire code block with gray background
            textStorage.addAttributes([
                .backgroundColor: NSColor.quaternaryLabelColor,
                .foregroundColor: NSColor.secondaryLabelColor
            ], range: range)
        }

        inlineCodePattern?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            if !Self.hasIntersectingRange(excludedRanges, with: range) {
                excludedRanges.append(range)
                textStorage.addAttributes([
                    .backgroundColor: NSColor.quaternaryLabelColor
                ], range: range)
            }
        }

        excludedRanges.sort { $0.location < $1.location }

        // 2. Apply markdown rules only outside code blocks
        for rule in markdownRules {
            rule.pattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                let isInsideCode = Self.hasIntersectingRange(excludedRanges, with: matchRange)
                if !isInsideCode {
                    textStorage.addAttributes(rule.attributes, range: matchRange)
                }
            }
        }

        textStorage.endEditing()
    }

    func highlight(_ textStorage: NSTextStorage, in editedRange: NSRange) {
        let text = textStorage.string
        let nsText = text as NSString

        guard nsText.length > 0 else { return }

        // Fence boundaries change global exclusion state, so any document
        // containing a fence must go through the full re-highlight path.
        guard !text.contains("```") else {
            highlight(textStorage)
            return
        }

        let clampedRange = NSIntersectionRange(editedRange, NSRange(location: 0, length: nsText.length))
        let range = nsText.paragraphRange(for: clampedRange)

        textStorage.beginEditing()

        // Reset to base attributes within the edited region
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor
        ], range: range)

        var excludedRanges: [NSRange] = []

        inlineCodePattern?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let matchRange = match?.range else { return }
            excludedRanges.append(matchRange)
            textStorage.addAttributes([
                .backgroundColor: NSColor.quaternaryLabelColor
            ], range: matchRange)
        }

        for rule in markdownRules {
            rule.pattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                let isInsideCode = excludedRanges.contains { NSIntersectionRange($0, matchRange).length > 0 }
                if !isInsideCode {
                    textStorage.addAttributes(rule.attributes, range: matchRange)
                }
            }
        }

        textStorage.endEditing()
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
