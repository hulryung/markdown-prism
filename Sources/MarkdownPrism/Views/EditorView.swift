import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.font = context.coordinator.highlighter.baseFont
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindPanel = true

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
    }
}
