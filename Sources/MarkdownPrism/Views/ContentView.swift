import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var markdownText = "# Markdown Prism\n\nOpen a `.md` file to preview **GFM**, `$x^2$`, and `mermaid` blocks."
    @State private var previewText = "# Markdown Prism\n\nOpen a `.md` file to preview **GFM**, `$x^2$`, and `mermaid` blocks."
    @State private var fileURL: URL?
    @State private var fileWatcher: FileWatcher?
    @State private var showEditor = true
    @State private var debounceWork: DispatchWorkItem?
    @State private var isModified = false

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
                Button(action: saveFile) {
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
        .onDisappear {
            fileWatcher?.stop()
            debounceWork?.cancel()
        }
        .onChange(of: markdownText) {
            schedulePreviewUpdate(markdownText)
        }
        .focusedSceneValue(\.newFileAction, { newFileAction() })
        .focusedSceneValue(\.openFileAction, { openFile() })
        .focusedSceneValue(\.saveFileAction, isModified ? { saveFile() } : nil)
        .focusedSceneValue(\.saveAsFileAction, { saveAsFile() })
    }

    private var windowTitle: String {
        guard let name = fileURL?.lastPathComponent else {
            return "Markdown Prism"
        }
        return isModified ? "\(name) \u{2014} Edited" : name
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
        markdownText = ""
        previewText = ""
        isModified = false
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

    private func saveFile() {
        guard let fileURL else {
            saveAsFile()
            return
        }
        writeFile(to: fileURL)
    }

    private func saveAsFile() {
        let panel = NSSavePanel()
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        panel.message = "Save Markdown file"

        if panel.runModal() == .OK, let url = panel.url {
            writeFile(to: url)
            if url != fileURL {
                fileURL = url
                startWatchingFile(at: url, forceRestart: true)
            }
        }
    }

    private func writeFile(to url: URL) {
        do {
            try markdownText.write(to: url, atomically: true, encoding: .utf8)
            isModified = false
        } catch {
            let alert = NSAlert()
            alert.messageText = "Save Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
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
            saveFile()
            return true
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
            markdownText = document.text
            previewText = document.text
            fileURL = url
            isModified = false
            startWatchingFile(at: url, forceRestart: previousURL != url)
        } catch {
            markdownText = "Error loading file: \(error.localizedDescription)"
            previewText = markdownText
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
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else {
                return
            }

            DispatchQueue.main.async {
                loadFile(url)
            }
        }

        return true
    }
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
