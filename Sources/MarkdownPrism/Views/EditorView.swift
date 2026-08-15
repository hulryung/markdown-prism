import SwiftUI
import AppKit

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let fontFamily: String
    let searchText: String
    let searchRevision: Int
    let isRegex: Bool
    let replaceText: String
    let replaceRevision: Int
    let replaceAllRevision: Int
    let scrollSync: ScrollSyncBus
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

        textView.textContainerInset = NSSize(width: LineNumberGutter.padding, height: 8)
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
        context.coordinator.rebuildLineIndex(for: text)

        scrollView.documentView = textView
        context.coordinator.observeScrolling(of: scrollView)
        context.coordinator.bind(to: scrollSync)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        let fontChanged = context.coordinator.appliedFontSize != fontSize
            || context.coordinator.appliedFontFamily != fontFamily
        context.coordinator.highlighter.fontSize = fontSize
        context.coordinator.highlighter.fontFamily = fontFamily
        let fontSizeChanged = fontChanged
        if fontSizeChanged {
            context.coordinator.applyTypingAttributes(to: textView)
            context.coordinator.applyGutterFont(to: textView, fontSize: fontSize)
        }

        let textChanged: Bool
        if context.coordinator.isEditingFromTextView {
            textChanged = false
        } else {
            textChanged = textView.string != text
        }
        if textChanged {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.noteExternalTextChange()
            context.coordinator.rebuildLineIndex(for: text)
        }
        context.coordinator.bind(to: scrollSync)

        // Re-highlight only when text changed externally or font size changed.
        // Per-keystroke highlights are debounced in textDidChange.
        if textChanged || fontSizeChanged {
            context.coordinator.cancelPendingHighlight()
            if let textStorage = textView.textStorage {
                let selectedRanges = textView.selectedRanges
                context.coordinator.highlighter.highlight(textStorage)
                textView.selectedRanges = selectedRanges
            }
        }
        context.coordinator.appliedFontSize = fontSize
        context.coordinator.appliedFontFamily = fontFamily
        context.coordinator.handleReplaceIfNeeded(in: textView)
        context.coordinator.updateSearchHighlights(in: textView)
        context.coordinator.isEditingFromTextView = false
    }

    final class EditorTextView: NSTextView {
        weak var coordinator: Coordinator?

        var gutter = LineNumberGutter() {
            didSet {
                // The container is inset by the gutter width so the text never
                // runs underneath the numbers.
                let width = gutter.width
                if textContainerInset.width != width {
                    textContainerInset = NSSize(width: width, height: textContainerInset.height)
                }
                needsDisplay = true
            }
        }

        override func drawBackground(in rect: NSRect) {
            super.drawBackground(in: rect)
            guard let layoutManager, let textContainer else { return }
            gutter.draw(
                in: rect,
                layoutManager: layoutManager,
                container: textContainer,
                containerInset: textContainerInset,
                bounds: bounds
            )
        }

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
        var appliedFontSize: CGFloat
        var appliedFontFamily = ""
        private var highlightWork: DispatchWorkItem?
        private static let highlightDebounceInterval: TimeInterval = 0.15
        private var textRevision = 0
        private var appliedTextRevision = -1
        fileprivate var isEditingFromTextView = false

        init(_ parent: EditorView) {
            self.parent = parent
            self.appliedFontSize = parent.fontSize
            highlighter = MarkdownHighlighter(fontSize: parent.fontSize, fontFamily: parent.fontFamily)
            appliedFontFamily = parent.fontFamily
        }

        deinit {
            highlightWork?.cancel()
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditingFromTextView = true
            textRevision += 1
            let editedRange = textView.selectedRange()
            parent.text = textView.string
            rebuildLineIndex(for: textView.string)
            clearStrayCodeBackground(in: textView)
            scheduleHighlight(for: textView, editedRange: editedRange)
        }

        // MARK: - Scroll Sync

        private var lineIndex = LineIndex("")
        private var scrollObserver: NSObjectProtocol?
        private var lastReportedLine = -1
        private var suppressScrollReportUntil = Date.distantPast
        private weak var scrollSync: ScrollSyncBus?

        func rebuildLineIndex(for text: String) {
            lineIndex = LineIndex(text)
            if let editor = textView as? EditorTextView {
                var gutter = editor.gutter
                gutter.lineIndex = lineIndex
                editor.gutter = gutter
            }
        }

        func bind(to scrollSync: ScrollSyncBus) {
            self.scrollSync = scrollSync
            scrollSync.scrollEditor = { [weak self] line in
                self?.scroll(toLine: line)
            }
        }

        func observeScrolling(of scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                scrollView.documentView?.needsDisplay = true
                self.reportScroll(in: scrollView)
            }
        }

        private func reportScroll(in scrollView: NSScrollView) {
            guard Date() >= suppressScrollReportUntil,
                  let textView = scrollView.documentView as? NSTextView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }

            let top = scrollView.contentView.bounds.minY - textView.textContainerInset.height
            let glyphIndex = layoutManager.glyphIndex(
                for: CGPoint(x: 0, y: max(0, top)),
                in: container
            )
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let line = lineIndex.line(forOffset: charIndex)

            guard line != lastReportedLine else { return }
            lastReportedLine = line
            scrollSync?.editorDidScroll(toLine: line)
        }

        private func scroll(toLine line: Int) {
            guard let textView,
                  let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }

            let offset = lineIndex.offset(forLine: line)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: offset, length: 0),
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)

            // The scroll we are about to make would otherwise come back as a
            // user scroll and bounce the preview.
            suppressScrollReportUntil = Date().addingTimeInterval(0.1)
            lastReportedLine = line
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: rect.minY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func cancelPendingHighlight() {
            highlightWork?.cancel()
            highlightWork = nil
        }

        fileprivate func noteExternalTextChange() {
            textRevision += 1
        }

        private func scheduleHighlight(for textView: NSTextView, editedRange: NSRange) {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self,
                      let textView,
                      let textStorage = textView.textStorage else { return }
                let selectedRanges = textView.selectedRanges
                self.highlighter.highlight(textStorage, in: editedRange)
                textView.selectedRanges = selectedRanges
                // Re-styling the paragraph resets the storage, not the caret's
                // own attributes, which are what the next keystroke uses.
                self.clearStrayCodeBackground(in: textView)
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.highlightDebounceInterval,
                execute: work
            )
        }

        func applyGutterFont(to textView: NSTextView, fontSize: CGFloat) {
            guard let editor = textView as? EditorTextView else { return }
            var gutter = editor.gutter
            gutter.font = .monospacedDigitSystemFont(ofSize: max(9, fontSize - 2), weight: .regular)
            editor.gutter = gutter
        }

        func applyTypingAttributes(to textView: NSTextView) {
            // Only set the default font. Let NSTextView's typingAttributes
            // inherit naturally from surrounding characters so typing inside
            // styled regions (bold, headers, etc.) keeps the style instead of
            // flashing to plain until the next debounced re-highlight.
            textView.font = highlighter.baseFont
        }

        private func clearStrayCodeBackground(in textView: NSTextView) {
            textView.clearStrayCodeBackground(using: highlighter)
        }

        // MARK: - Search

        private var searchMatches: [NSRange] = []
        private var searchMatchIndex = -1
        private var appliedSearchText = ""
        private var appliedSearchRevision = 0
        private var appliedIsRegex = false

        func updateSearchHighlights(in textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textStorage = textView.textStorage else { return }

            let query = parent.searchText
            let queryChanged = query != appliedSearchText || parent.isRegex != appliedIsRegex
            let revisionChanged = parent.searchRevision != appliedSearchRevision
            let textChanged = textRevision != appliedTextRevision

            guard queryChanged || revisionChanged || textChanged else { return }

            if query.isEmpty && appliedSearchText.isEmpty {
                appliedTextRevision = textRevision
                return
            }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

            guard !query.isEmpty else {
                searchMatches = []
                searchMatchIndex = -1
                appliedSearchText = ""
                appliedTextRevision = textRevision
                return
            }

            // Find all matches
            var matches: [NSRange] = []
            let text = textStorage.string
            let nsString = text as NSString

            if parent.isRegex {
                guard let regex = try? NSRegularExpression(pattern: query, options: .caseInsensitive) else {
                    searchMatches = []
                    searchMatchIndex = -1
                    appliedSearchText = query
                    appliedIsRegex = parent.isRegex
                    appliedTextRevision = textRevision
                    return
                }
                matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length)).map { $0.range }
            } else {
                var range = NSRange(location: 0, length: nsString.length)
                while range.location < nsString.length {
                    let found = nsString.range(of: query, options: .caseInsensitive, range: range)
                    guard found.location != NSNotFound else { break }
                    matches.append(found)
                    range.location = found.location + found.length
                    range.length = nsString.length - range.location
                }
            }
            searchMatches = matches

            let revision = parent.searchRevision

            if queryChanged {
                searchMatchIndex = matches.isEmpty ? -1 : 0
                appliedSearchText = query
                appliedIsRegex = parent.isRegex
                appliedSearchRevision = revision
            } else if revisionChanged {
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

            if queryChanged || revisionChanged,
               searchMatchIndex >= 0 && searchMatchIndex < matches.count {
                textView.scrollRangeToVisible(matches[searchMatchIndex])
            }

            appliedTextRevision = textRevision
        }

        // MARK: - Replace

        private var appliedReplaceRevision = 0
        private var appliedReplaceAllRevision = 0

        func handleReplaceIfNeeded(in textView: NSTextView) {
            let rev = parent.replaceRevision
            if rev != appliedReplaceRevision {
                appliedReplaceRevision = rev
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.replaceCurrent(in: textView)
                }
            }
            let allRev = parent.replaceAllRevision
            if allRev != appliedReplaceAllRevision {
                appliedReplaceAllRevision = allRev
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    self.replaceAllMatches(in: textView)
                }
            }
        }

        private func replaceCurrent(in textView: NSTextView) {
            guard searchMatchIndex >= 0, searchMatchIndex < searchMatches.count,
                  let textStorage = textView.textStorage else { return }
            let match = searchMatches[searchMatchIndex]
            var replacement = parent.replaceText

            if parent.isRegex,
               let regex = try? NSRegularExpression(pattern: parent.searchText, options: .caseInsensitive),
               let result = regex.firstMatch(in: textStorage.string, range: match) {
                replacement = regex.replacementString(for: result, in: textStorage.string, offset: 0, template: parent.replaceText)
            }

            if textView.shouldChangeText(in: match, replacementString: replacement) {
                textStorage.replaceCharacters(in: match, with: replacement)
                textView.didChangeText()
            }
        }

        private func replaceAllMatches(in textView: NSTextView) {
            guard !searchMatches.isEmpty, let textStorage = textView.textStorage else { return }
            let originalText = textStorage.string
            let replacement = parent.replaceText

            var replacements: [(NSRange, String)] = []

            if parent.isRegex,
               let regex = try? NSRegularExpression(pattern: parent.searchText, options: .caseInsensitive) {
                for match in searchMatches {
                    if let result = regex.firstMatch(in: originalText, range: match) {
                        let expanded = regex.replacementString(for: result, in: originalText, offset: 0, template: replacement)
                        replacements.append((match, expanded))
                    }
                }
            } else {
                replacements = searchMatches.map { ($0, replacement) }
            }

            var newText = originalText
            for (range, text) in replacements.reversed() {
                guard let swiftRange = Range(range, in: newText) else { continue }
                newText.replaceSubrange(swiftRange, with: text)
            }

            let fullRange = NSRange(location: 0, length: textStorage.length)
            if textView.shouldChangeText(in: fullRange, replacementString: newText) {
                textStorage.replaceCharacters(in: fullRange, with: newText)
                textView.didChangeText()
            }
        }
    }
}

extension NSTextView {
    /// Stops the code background following the caret out of a code span.
    ///
    /// Typing attributes are inherited from the character before the caret,
    /// deliberately: that is what keeps typing inside bold or a heading from
    /// flashing plain until the debounced re-highlight catches up. Those styles
    /// are carried by the font and the foreground colour. The background is
    /// carried by code alone — and an inline span ends on a backtick, so a caret
    /// sitting after one inherits a background belonging to the character behind
    /// it and hands it to everything typed next.
    ///
    /// Newlines included, which is what made it visible: a styled newline draws
    /// as a band across the full width of the line rather than behind any words.
    ///
    /// Cleared eagerly rather than left to the next highlight, which resets only
    /// the paragraph the edit was in — a background carried into an earlier
    /// paragraph would never be reset at all.
    ///
    /// Inside a fenced block the inheritance is right, and is left alone.
    func clearStrayCodeBackground(using highlighter: MarkdownHighlighter) {
        guard typingAttributes[.backgroundColor] != nil else { return }
        guard !highlighter.isInsideCodeBlock(string, at: selectedRange().location) else { return }
        typingAttributes.removeValue(forKey: .backgroundColor)
    }
}
