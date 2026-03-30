import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var openFileState: OpenFileState
    @AppStorage("zoomScale") private var zoomScale = ZoomState.defaultScale
    @State private var markdownText = ContentView.welcomeMarkdown
    @State private var previewText = ContentView.welcomeMarkdown
    @State private var fileURL: URL?
    @State private var fileWatcher: FileWatcher?
    @State private var showEditor = true
    @State private var debounceWork: DispatchWorkItem?
    @State private var isModified = false
    @State private var ignoreNextTextChange = false
    @State private var isSearchVisible = false
    @State private var searchText = ""
    @State private var searchMatchCount = 0
    @State private var searchCurrentMatch = 0
    @State private var searchRevision = 0
    @State private var findBarFocusTrigger = 0
    @State private var isRegex = false
    @State private var replaceText = ""
    @State private var isReplaceVisible = false
    @State private var replaceRevision = 0
    @State private var replaceAllRevision = 0

    var body: some View {
        innerBody
            .focusedSceneValue(\.findAction, { showSearch() })
            .focusedSceneValue(\.findNextAction, isSearchVisible ? { findNext() } : nil)
            .focusedSceneValue(\.findPreviousAction, isSearchVisible ? { findPrevious() } : nil)
            .focusedSceneValue(\.dismissFindAction, isSearchVisible ? { dismissSearch() } : nil)
            .focusedSceneValue(\.showReplaceAction, { showReplace() })
    }



    @ViewBuilder
    private var findBar: some View {
        if isSearchVisible {
            FindBarView(
                searchText: $searchText,
                replaceText: $replaceText,
                isRegex: $isRegex,
                isReplaceVisible: isReplaceVisible,
                matchCount: searchMatchCount,
                currentMatch: searchCurrentMatch,
                focusTrigger: findBarFocusTrigger,
                onNext: findNext,
                onPrevious: findPrevious,
                onDismiss: dismissSearch,
                onToggleReplace: { isReplaceVisible.toggle() },
                onReplace: { replaceRevision += 1 },
                onReplaceAll: { replaceAllRevision += 1 }
            )
        }
    }

    private var innerBody: some View {
        VStack(spacing: 0) {
            findBar
            HSplitView {
                if showEditor {
                    editorPane
                }
                previewPane
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showEditor.toggle() }) {
                    Label(
                        showEditor ? "Hide Editor" : "Show Editor",
                        systemImage: showEditor ? "rectangle.lefthalf.filled" : "rectangle.split.2x1"
                    )
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .automatic) {
                Button(action: openFile) {
                    Label("Open", systemImage: "doc")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { _ = saveFile() }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isModified)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: refreshFile) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(fileURL == nil)
            }
            ToolbarItemGroup(placement: .automatic) {
                Button(action: zoomOut) {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(!zoomState.canZoomOut)

                Button(action: zoomIn) {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(!zoomState.canZoomIn)
            }
        }
        .navigationTitle(windowTitle)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onOpenURL { url in
            loadFile(url)
        }
        .onChange(of: openFileState.pendingURL) {
            if let url = openFileState.pendingURL {
                openFileState.pendingURL = nil
                loadFile(url)
            }
        }
        .onAppear {
            if let url = openFileState.pendingURL {
                openFileState.pendingURL = nil
                loadFile(url)
            }
        }
        .onDisappear {
            fileWatcher?.stop()
            debounceWork?.cancel()
        }
        .onChange(of: markdownText) {
            if ignoreNextTextChange {
                ignoreNextTextChange = false
                return
            }
            schedulePreviewUpdate(markdownText)
        }
        .focusedSceneValue(\.newFileAction, { newFileAction() })
        .focusedSceneValue(\.openFileAction, { openFile() })
        .focusedSceneValue(\.saveFileAction, isModified ? { _ = saveFile() } : nil)
        .focusedSceneValue(\.saveAsFileAction, { _ = saveAsFile() })
        .focusedSceneValue(\.zoomInAction, zoomState.canZoomIn ? { zoomIn() } : nil)
        .focusedSceneValue(\.zoomOutAction, zoomState.canZoomOut ? { zoomOut() } : nil)
        .focusedSceneValue(\.resetZoomAction, zoomState.zoomScale == ZoomState.defaultScale ? nil : { resetZoom() })
    }

    private var windowTitle: String {
        guard let name = fileURL?.lastPathComponent else {
            return "Markdown Prism"
        }
        return isModified ? "\(name) \u{2014} Edited" : name
    }

    private var zoomState: ZoomState {
        ZoomState(zoomScale: zoomScale)
    }

    private var activeSearchText: String {
        isSearchVisible ? searchText : ""
    }

    private var editorPane: some View {
        EditorView(
            text: $markdownText,
            fontSize: zoomState.editorFontSize,
            searchText: activeSearchText,
            searchRevision: searchRevision,
            isRegex: isRegex,
            replaceText: replaceText,
            replaceRevision: replaceRevision,
            replaceAllRevision: replaceAllRevision,
            onEscapePressed: isSearchVisible ? dismissSearch : nil
        )
        .frame(minWidth: 300)
    }

    private var previewPane: some View {
        PreviewView(
            markdown: previewText,
            zoomScale: zoomState.zoomScale,
            searchText: activeSearchText,
            searchRevision: searchRevision,
            isRegex: isRegex,
            fileURL: fileURL,
            onOpenFile: { url in loadFile(url) },
            onSearchResults: { count, current in
                searchMatchCount = count
                searchCurrentMatch = current
            }
        )
        .frame(minWidth: 300)
    }

    private func setDocumentText(_ text: String, modified: Bool) {
        ignoreNextTextChange = true
        markdownText = text
        previewText = text
        isModified = modified
    }

    private func zoomIn() {
        var nextZoomState = zoomState
        nextZoomState.zoomIn()
        zoomScale = nextZoomState.zoomScale
    }

    private func zoomOut() {
        var nextZoomState = zoomState
        nextZoomState.zoomOut()
        zoomScale = nextZoomState.zoomScale
    }

    private func resetZoom() {
        var nextZoomState = zoomState
        nextZoomState.reset()
        zoomScale = nextZoomState.zoomScale
    }

    private func showSearch() {
        isSearchVisible = true
        findBarFocusTrigger += 1
    }

    private func dismissSearch() {
        isSearchVisible = false
        isReplaceVisible = false
        searchText = ""
        replaceText = ""
        searchMatchCount = 0
        searchCurrentMatch = 0
    }

    private func showReplace() {
        isSearchVisible = true
        isReplaceVisible = true
        findBarFocusTrigger += 1
    }

    private func findNext() {
        searchRevision += 1
    }

    private func findPrevious() {
        searchRevision -= 1
    }

    private func schedulePreviewUpdate(_ text: String) {
        debounceWork?.cancel()
        let work = DispatchWorkItem {
            previewText = text
            isModified = true
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - File Actions

    private func newFileAction() {
        if isModified {
            guard confirmDiscardChanges() else { return }
        }
        fileWatcher?.stop()
        fileWatcher = nil
        fileURL = nil
        setDocumentText("", modified: false)
    }

    private func openFile() {
        if isModified {
            guard confirmDiscardChanges() else { return }
        }

        let panel = NSOpenPanel()
        var contentTypes: [UTType] = [.plainText]
        if let markdownType = UTType(filenameExtension: "md") {
            contentTypes.insert(markdownType, at: 0)
        }
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Markdown file"

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(url)
        }
    }

    private func saveFile() -> Bool {
        guard let fileURL else {
            return saveAsFile()
        }
        return writeFile(to: fileURL)
    }

    private func saveAsFile() -> Bool {
        let panel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        panel.message = "Save Markdown file"

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        guard writeFile(to: url) else {
            return false
        }

        if url != fileURL {
            fileURL = url
            startWatchingFile(at: url, forceRestart: true)
        }

        return true
    }

    private func writeFile(to url: URL) -> Bool {
        do {
            try markdownText.write(to: url, atomically: true, encoding: .utf8)
            isModified = false
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    private func confirmDiscardChanges() -> Bool {
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Do you want to save your changes before continuing?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return saveFile()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func loadFile(_ url: URL) {
        let previousURL = fileURL
        do {
            let document = try MarkdownDocument(fileURL: url)
            setDocumentText(document.text, modified: false)
            fileURL = url
            startWatchingFile(at: url, forceRestart: previousURL != url)
        } catch {
            let message = "Error loading file: \(error.localizedDescription)"
            setDocumentText(message, modified: false)
        }
    }

    private func refreshFile() {
        guard let fileURL else {
            return
        }
        loadFile(fileURL)
    }

    private func startWatchingFile(at url: URL, forceRestart: Bool) {
        guard forceRestart || fileWatcher == nil else {
            return
        }

        fileWatcher?.stop()
        fileWatcher = FileWatcher(url: url) {
            DispatchQueue.main.async {
                guard self.fileURL == url else {
                    return
                }
                self.loadFile(url)
            }
        }
        fileWatcher?.start()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let droppedURL: URL?
            if let url = item as? URL {
                droppedURL = url
            } else if let data = item as? Data {
                droppedURL = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                droppedURL = nil
            }

            guard let url = droppedURL else {
                return
            }

            DispatchQueue.main.async {
                if self.isModified {
                    guard self.confirmDiscardChanges() else {
                        return
                    }
                }
                self.loadFile(url)
            }
        }

        return true
    }
}

// MARK: - Welcome Demo Content

extension ContentView {
    static let welcomeMarkdown = """
    # Welcome to Markdown Prism

    A native macOS Markdown viewer & editor with **live preview**.

    ---

    ## Features

    ### Text Formatting

    **Bold**, *Italic*, ~~Strikethrough~~, and `inline code`.

    > Blockquotes are supported too.
    > They can span multiple lines.

    ### Links & Images

    Visit [GitHub](https://github.com) or check the [Markdown Guide](https://www.markdownguide.org).

    ### Lists

    - Unordered item 1
    - Unordered item 2
      - Nested item

    1. Ordered item 1
    2. Ordered item 2

    ### Task Lists

    - [x] GFM Markdown rendering
    - [x] Syntax highlighting
    - [x] LaTeX math support
    - [x] Mermaid diagrams
    - [ ] Quick Look extension

    ### Tables

    | Feature | Status | Notes |
    |:--------|:------:|------:|
    | GFM | Done | Tables, task lists |
    | KaTeX | Done | Inline & block math |
    | Mermaid | Done | Flowcharts & more |
    | highlight.js | Done | 180+ languages |

    ### Code Blocks

    ```swift
    // Swift example
    struct MarkdownPrism: App {
        var body: some Scene {
            WindowGroup {
                ContentView()
            }
        }
    }
    ```

    ```python
    # Python example
    def fibonacci(n):
        a, b = 0, 1
        for _ in range(n):
            a, b = b, a + b
        return a

    print(fibonacci(10))  # 55
    ```

    ### Math (KaTeX)

    Inline math: $E = mc^2$, $\\alpha + \\beta = \\gamma$

    Block math:

    $$
    \\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}
    $$

    $$
    \\sum_{n=1}^{\\infty} \\frac{1}{n^2} = \\frac{\\pi^2}{6}
    $$

    ### Mermaid Diagrams

    ```mermaid
    graph LR
        A[Markdown] --> B[markdown-it]
        B --> C[HTML]
        C --> D[highlight.js]
        C --> E[KaTeX]
        C --> F[Mermaid]
        D --> G[Rendered Preview]
        E --> G
        F --> G
    ```

    ---

    **Tip:** Open a `.md` file with **Cmd+O** or drag & drop it onto this window.
    """
}

// MARK: - Focused Values for Menu Commands

private struct NewFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct OpenFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SaveFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SaveAsFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ZoomInActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ZoomOutActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ResetZoomActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FindActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FindNextActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct FindPreviousActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DismissFindActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ShowReplaceActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newFileAction: (() -> Void)? {
        get { self[NewFileActionKey.self] }
        set { self[NewFileActionKey.self] = newValue }
    }

    var openFileAction: (() -> Void)? {
        get { self[OpenFileActionKey.self] }
        set { self[OpenFileActionKey.self] = newValue }
    }

    var saveFileAction: (() -> Void)? {
        get { self[SaveFileActionKey.self] }
        set { self[SaveFileActionKey.self] = newValue }
    }

    var saveAsFileAction: (() -> Void)? {
        get { self[SaveAsFileActionKey.self] }
        set { self[SaveAsFileActionKey.self] = newValue }
    }

    var zoomInAction: (() -> Void)? {
        get { self[ZoomInActionKey.self] }
        set { self[ZoomInActionKey.self] = newValue }
    }

    var zoomOutAction: (() -> Void)? {
        get { self[ZoomOutActionKey.self] }
        set { self[ZoomOutActionKey.self] = newValue }
    }

    var resetZoomAction: (() -> Void)? {
        get { self[ResetZoomActionKey.self] }
        set { self[ResetZoomActionKey.self] = newValue }
    }

    var findAction: (() -> Void)? {
        get { self[FindActionKey.self] }
        set { self[FindActionKey.self] = newValue }
    }

    var findNextAction: (() -> Void)? {
        get { self[FindNextActionKey.self] }
        set { self[FindNextActionKey.self] = newValue }
    }

    var findPreviousAction: (() -> Void)? {
        get { self[FindPreviousActionKey.self] }
        set { self[FindPreviousActionKey.self] = newValue }
    }

    var dismissFindAction: (() -> Void)? {
        get { self[DismissFindActionKey.self] }
        set { self[DismissFindActionKey.self] = newValue }
    }

    var showReplaceAction: (() -> Void)? {
        get { self[ShowReplaceActionKey.self] }
        set { self[ShowReplaceActionKey.self] = newValue }
    }
}
