import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var openFileState: OpenFileState
    @State private var markdownText = ContentView.welcomeMarkdown
    @State private var previewText = ContentView.welcomeMarkdown
    @State private var fileURL: URL?
    @State private var fileWatcher: FileWatcher?
    @State private var showEditor = true
    @State private var debounceWork: DispatchWorkItem?
    @State private var isModified = false
    @State private var ignoreNextTextChange = false

    var body: some View {
        HSplitView {
            if showEditor {
                EditorView(text: $markdownText)
                    .frame(minWidth: 300)
            }
            PreviewView(markdown: previewText)
                .frame(minWidth: 300)
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
    }

    private var windowTitle: String {
        guard let name = fileURL?.lastPathComponent else {
            return "Markdown Prism"
        }
        return isModified ? "\(name) \u{2014} Edited" : name
    }

    private func setDocumentText(_ text: String, modified: Bool) {
        ignoreNextTextChange = true
        markdownText = text
        previewText = text
        isModified = modified
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
}
