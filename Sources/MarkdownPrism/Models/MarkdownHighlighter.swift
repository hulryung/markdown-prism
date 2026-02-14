import AppKit

final class MarkdownHighlighter {
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private let baseColor = NSColor.labelColor

    private struct HighlightRule {
        let pattern: NSRegularExpression
        let attributes: [NSAttributedString.Key: Any]
    }

    private let rules: [HighlightRule]

    init() {
        var rules: [HighlightRule] = []

        let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let headerFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)

        // Headers: ^#{1,6}\s.+$
        if let regex = try? NSRegularExpression(pattern: "^#{1,6}\\s.+$", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .font: headerFont,
                .foregroundColor: NSColor.systemBlue
            ]))
        }

        // Bold: **text** or __text__
        if let regex = try? NSRegularExpression(pattern: "(\\*\\*.+?\\*\\*|__.+?__)", options: []) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .font: boldFont
            ]))
        }

        // Italic: *text* or _text_ (negative lookbehind/ahead for * to avoid matching **)
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

        // Fenced code blocks: ```...``` (multiline)
        if let regex = try? NSRegularExpression(pattern: "^```[\\s\\S]*?^```", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .backgroundColor: NSColor.quaternaryLabelColor
            ]))
        }

        // Inline code: `code`
        if let regex = try? NSRegularExpression(pattern: "`[^`]+`", options: []) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .backgroundColor: NSColor.quaternaryLabelColor
            ]))
        }

        // Links: [text](url)
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)", options: []) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .foregroundColor: NSColor.systemBlue
            ]))
        }

        // Blockquotes: ^> text
        if let regex = try? NSRegularExpression(pattern: "^>\\s.+$", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }

        // List markers: bullets or numbered
        if let regex = try? NSRegularExpression(pattern: "^(\\s*[-*+]|\\s*\\d+\\.)\\s", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .foregroundColor: NSColor.systemOrange
            ]))
        }

        // Horizontal rules: ---, ***, ___
        if let regex = try? NSRegularExpression(pattern: "^(-{3,}|\\*{3,}|_{3,})$", options: .anchorsMatchLines) {
            rules.append(HighlightRule(pattern: regex, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }

        self.rules = rules
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

        // Apply each rule
        for rule in rules {
            rule.pattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let matchRange = match?.range else { return }
                textStorage.addAttributes(rule.attributes, range: matchRange)
            }
        }

        textStorage.endEditing()
    }
}
