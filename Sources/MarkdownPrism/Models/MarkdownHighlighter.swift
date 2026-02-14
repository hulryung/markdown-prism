import AppKit

final class MarkdownHighlighter {
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let baseColor = NSColor.labelColor

    private let codeBlockPattern: NSRegularExpression?
    private let inlineCodePattern: NSRegularExpression?

    private struct HighlightRule {
        let pattern: NSRegularExpression
        let attributes: [NSAttributedString.Key: Any]
    }

    private let markdownRules: [HighlightRule]

    init() {
        codeBlockPattern = try? NSRegularExpression(pattern: "^```[\\s\\S]*?^```", options: .anchorsMatchLines)
        inlineCodePattern = try? NSRegularExpression(pattern: "`[^`\n]+`", options: [])

        var rules: [HighlightRule] = []

        let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let headerFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)

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
            let italicDescriptor = NSFontDescriptor(fontAttributes: [
                .family: "Menlo",
                .face: "Italic"
            ])
            let italicFont = NSFont(descriptor: italicDescriptor, size: 14)
                ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
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

        self.markdownRules = rules
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
            if !excludedRanges.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
                excludedRanges.append(range)
                textStorage.addAttributes([
                    .backgroundColor: NSColor.quaternaryLabelColor
                ], range: range)
            }
        }

        // 2. Apply markdown rules only outside code blocks
        for rule in markdownRules {
            rule.pattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                let isInsideCode = excludedRanges.contains { NSIntersectionRange($0, matchRange).length > 0 }
                if !isInsideCode {
                    textStorage.addAttributes(rule.attributes, range: matchRange)
                }
            }
        }

        textStorage.endEditing()
    }
}
