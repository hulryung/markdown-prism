import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let searchText: String
    let searchRevision: Int
    var onEscapePressed: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = EditorTextView()
        textView.coordinator = context.coordinator
        textView.font = context.coordinator.highlighter.baseFont
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindPanel = false

        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.applyTypingAttributes(to: textView)

        textView.string = text
        context.coordinator.highlighter.highlight(textView.textStorage!)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        context.coordinator.highlighter.fontSize = fontSize
        context.coordinator.applyTypingAttributes(to: textView)

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            context.coordinator.highlighter.highlight(textView.textStorage!)
            textView.selectedRanges = selectedRanges
        } else {
            let selectedRanges = textView.selectedRanges
            context.coordinator.highlighter.highlight(textView.textStorage!)
            textView.selectedRanges = selectedRanges
        }
        context.coordinator.updateSearchHighlights(in: textView)
    }

    final class EditorTextView: NSTextView {
        weak var coordinator: Coordinator?

        override func cancelOperation(_ sender: Any?) {
            if let onEscape = coordinator?.parent.onEscapePressed {
                onEscape()
            } else {
                super.cancelOperation(sender)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        weak var textView: NSTextView?
        let highlighter: MarkdownHighlighter

        init(_ parent: EditorView) {
            self.parent = parent
            highlighter = MarkdownHighlighter(fontSize: parent.fontSize)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string

            let selectedRanges = textView.selectedRanges
            highlighter.highlight(textView.textStorage!)
            textView.selectedRanges = selectedRanges
        }

        func applyTypingAttributes(to textView: NSTextView) {
            textView.font = highlighter.baseFont
            textView.typingAttributes[.font] = highlighter.baseFont
            textView.typingAttributes[.foregroundColor] = NSColor.labelColor
        }

        private var searchMatches: [NSRange] = []
        private var searchMatchIndex = -1
        private var appliedSearchText = ""
        private var appliedSearchRevision = 0

        func updateSearchHighlights(in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textStorage = textView.textStorage else { return }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

            let query = parent.searchText
            guard !query.isEmpty else {
                searchMatches = []
                searchMatchIndex = -1
                appliedSearchText = ""
                return
            }

            // Find all matches
            var matches: [NSRange] = []
            let nsString = textStorage.string as NSString
            var range = NSRange(location: 0, length: nsString.length)
            while range.location < nsString.length {
                let found = nsString.range(of: query, options: .caseInsensitive, range: range)
                guard found.location != NSNotFound else { break }
                matches.append(found)
                range.location = found.location + found.length
                range.length = nsString.length - range.location
            }
            searchMatches = matches

            let revision = parent.searchRevision

            if query != appliedSearchText {
                searchMatchIndex = matches.isEmpty ? -1 : 0
                appliedSearchText = query
                appliedSearchRevision = revision
            } else if revision != appliedSearchRevision {
                if !matches.isEmpty {
                    if revision > appliedSearchRevision {
                        searchMatchIndex = (searchMatchIndex + 1) % matches.count
                    } else {
                        searchMatchIndex = (searchMatchIndex - 1 + matches.count) % matches.count
                    }
                }
                appliedSearchRevision = revision
            }

            // Apply highlights
            let highlightColor = NSColor.systemYellow.withAlphaComponent(0.3)
            let currentColor = NSColor.systemOrange.withAlphaComponent(0.5)

            for (i, match) in matches.enumerated() {
                let color = (i == searchMatchIndex) ? currentColor : highlightColor
                layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: match)
            }

            // Scroll to current match
            if searchMatchIndex >= 0 && searchMatchIndex < matches.count {
                textView.scrollRangeToVisible(matches[searchMatchIndex])
            }
        }
    }
}
