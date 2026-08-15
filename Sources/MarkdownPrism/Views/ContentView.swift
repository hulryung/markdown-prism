import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Binding var document: MarkdownFileDocument
    let fileURL: URL?

    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var diff = DiffSession()
    @AppStorage("zoomScale") private var zoomScale = ZoomState.defaultScale
    @AppStorage("useFullWidth") private var useFullWidth = false
    @State private var previewText = ""
    @State private var scrollSync = ScrollSyncBus()
    @State private var fileWatcher: FileWatcher?
    @State private var showEditor = true
    @State private var debounceWork: DispatchWorkItem?
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
    @State private var changeRevision = 0
    @State private var changeCount = 0
    @State private var currentChange = 0

    var body: some View {
        innerBody
            .focusedSceneValue(
                \.diffCommand,
                DiffCommand(current: diff.baseline, select: { selectBaseline($0) })
            )
            .focusedSceneValue(\.nextChangeAction, changeCount > 0 ? { nextChange() } : nil)
            .focusedSceneValue(\.previousChangeAction, changeCount > 0 ? { previousChange() } : nil)
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

    @ViewBuilder
    private var diffBar: some View {
        if diff.baseline.isShowingChanges {
            DiffBarView(
                baseline: diff.baseline,
                state: diff.state,
                changeCount: changeCount,
                currentChange: currentChange,
                onNextChange: nextChange,
                onPreviousChange: previousChange,
                onGrantAccess: {
                    guard let fileURL else { return }
                    diff.requestAccess(for: fileURL, text: document.text)
                },
                onDismiss: { selectBaseline(.off) }
            )
        }
    }

    private var diffMenu: some View {
        Menu {
            Picker("Compare With", selection: baselineBinding) {
                ForEach(DiffBaseline.allCases) { baseline in
                    Text(baseline.label).tag(baseline)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(
                "Show Changes",
                systemImage: diff.baseline.isShowingChanges ? "plusminus.circle.fill" : "plusminus.circle"
            )
        }
        .help("Show changes against Git")
    }

    private var innerBody: some View {
        VStack(spacing: 0) {
            findBar
            diffBar
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
                diffMenu
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { useFullWidth.toggle() }) {
                    Label(
                        useFullWidth ? "Fixed Width" : "Full Width",
                        systemImage: useFullWidth ? "arrow.right.and.line.vertical.and.arrow.left" : "arrow.left.and.line.vertical.and.arrow.right"
                    )
                }
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
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onAppear {
            updateScrollSyncEnabled()
            previewText = document.text
            startWatchingFile()
        }
        .onChange(of: fileURL) {
            // Save As, Rename and Move To all repoint the document.
            startWatchingFile()
            diff.reload(for: fileURL, text: document.text)
        }
        .onChange(of: showEditor) {
            // Nothing to follow along with while the editor is hidden.
            updateScrollSyncEnabled()
        }
        .onChange(of: diff.state) {
            updateScrollSyncEnabled()
        }
        .onDisappear {
            debounceWork?.cancel()
            fileWatcher?.stop()
        }
        .onChange(of: document.text) {
            schedulePreviewUpdate(document.text)
        }
        .focusedSceneValue(\.zoomInAction, zoomState.canZoomIn ? { zoomIn() } : nil)
        .focusedSceneValue(\.zoomOutAction, zoomState.canZoomOut ? { zoomOut() } : nil)
        .focusedSceneValue(\.resetZoomAction, zoomState.zoomScale == ZoomState.defaultScale ? nil : { resetZoom() })
    }

    private var zoomState: ZoomState {
        ZoomState(zoomScale: zoomScale)
    }

    private var activeSearchText: String {
        isSearchVisible ? searchText : ""
    }

    private var editorPane: some View {
        EditorView(
            text: $document.text,
            fontSize: settings.editorFontSize * zoomState.zoomScale,
            fontFamily: settings.editorFontName,
            searchText: activeSearchText,
            searchRevision: searchRevision,
            isRegex: isRegex,
            replaceText: replaceText,
            replaceRevision: replaceRevision,
            replaceAllRevision: replaceAllRevision,
            scrollSync: scrollSync,
            onEscapePressed: isSearchVisible ? dismissSearch : nil
        )
        .frame(minWidth: 300)
    }

    /// What the preview renders. Comparing two stored revisions puts the later
    /// of them on screen; every other case shows the editor's own text.
    private var previewMarkdown: String {
        if case .ready(let comparison) = diff.state, let current = comparison.current {
            return current
        }
        return previewText
    }

    /// The version the preview marks its changes against, or nil to render the
    /// document plainly.
    private var previewBaseline: String? {
        guard case .ready(let comparison) = diff.state else { return nil }
        return comparison.baseline
    }

    private var previewPane: some View {
        PreviewView(
            markdown: previewMarkdown,
            baseline: previewBaseline,
            zoomScale: zoomState.zoomScale,
            searchText: activeSearchText,
            searchRevision: searchRevision,
            isRegex: isRegex,
            useFullWidth: useFullWidth,
            fontStack: settings.previewFontStack,
            fontSize: settings.previewFontSize,
            scrollSync: scrollSync,
            changeRevision: changeRevision,
            fileURL: fileURL,
            onOpenFile: { url in open(url) },
            onSearchResults: { count, current in
                searchMatchCount = count
                searchCurrentMatch = current
            },
            onChangesCounted: { count, current in
                changeCount = count
                currentChange = current
            }
        )
        .frame(minWidth: 300)
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
            // Only the counts move as the reader types; the stored side they are
            // counted against has not changed, so this reads no history.
            diff.updateCounts(for: text)
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - Showing Changes

    private var baselineBinding: Binding<DiffBaseline> {
        Binding(
            get: { diff.baseline },
            set: { selectBaseline($0) }
        )
    }

    private func selectBaseline(_ baseline: DiffBaseline) {
        diff.select(baseline, for: fileURL, text: document.text)
    }

    private func nextChange() {
        changeRevision += 1
    }

    private func previousChange() {
        changeRevision -= 1
    }

    /// Following the editor only makes sense while the preview is showing the
    /// editor's own text — comparing two stored revisions puts a document on
    /// screen that the cursor has no position in.
    private func updateScrollSyncEnabled() {
        let showingEditorText: Bool
        if case .ready(let comparison) = diff.state {
            showingEditorText = comparison.current == nil
        } else {
            showingEditorText = true
        }
        scrollSync.isEnabled = showEditor && showingEditorText
    }

    // MARK: - External Changes

    /// The document system does not notice a file changing underneath it, so
    /// the watcher stays and reloads through the document's own revert path —
    /// which re-reads the file and clears the edited state, rather than writing
    /// the new text in as if the user had typed it.
    private func startWatchingFile() {
        fileWatcher?.stop()
        fileWatcher = nil

        guard let fileURL else { return }
        fileWatcher = FileWatcher(url: fileURL) {
            DispatchQueue.main.async {
                reloadFromDisk(fileURL)
            }
        }
        fileWatcher?.start()
    }

    private func reloadFromDisk(_ url: URL) {
        guard self.fileURL == url,
              let nsDocument = NSDocumentController.shared.document(for: url) else { return }

        // The watcher cannot tell the app's own writes from anyone else's, and
        // the app writes often: autosaving in place saves while the reader is
        // still typing. Comparing what landed is what separates them, and it
        // needs no window of suppression around saving to get right.
        guard !MarkdownDocument.file(at: url, holds: document.text) else { return }

        if nsDocument.isDocumentEdited {
            let alert = NSAlert()
            alert.messageText = "The file was changed on disk"
            alert.informativeText = "Reload and discard your unsaved changes?"
            alert.addButton(withTitle: "Reload")
            alert.addButton(withTitle: "Keep My Changes")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        // Failures are silent: the watcher also fires mid-replace, while the
        // path is briefly gone, and the last good content should survive.
        try? nsDocument.revert(
            toContentsOf: url,
            ofType: nsDocument.fileType ?? UTType.markdown.identifier
        )

        // Whatever changed the file may well have been a git operation, so the
        // stored side is re-read rather than assumed to still be current.
        diff.reload(for: url, text: document.text)
    }

    /// Opens a file in its own document window, which is also what gives the
    /// sandbox access to it and adds it to Open Recent.
    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            guard let error else { return }
            let alert = NSAlert()
            alert.messageText = "Could not open \u{201C}\(url.lastPathComponent)\u{201D}"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
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
                open(url)
            }
        }

        return true
    }
}

// MARK: - Focused Values for Menu Commands

/// Lets the View menu drive the focused window's comparison, and show which one
/// it is already on.
struct DiffCommand {
    var current: DiffBaseline
    var select: (DiffBaseline) -> Void
}

private struct DiffCommandKey: FocusedValueKey {
    typealias Value = DiffCommand
}

private struct NextChangeActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct PreviousChangeActionKey: FocusedValueKey {
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
    var diffCommand: DiffCommand? {
        get { self[DiffCommandKey.self] }
        set { self[DiffCommandKey.self] = newValue }
    }

    var nextChangeAction: (() -> Void)? {
        get { self[NextChangeActionKey.self] }
        set { self[NextChangeActionKey.self] = newValue }
    }

    var previousChangeAction: (() -> Void)? {
        get { self[PreviousChangeActionKey.self] }
        set { self[PreviousChangeActionKey.self] = newValue }
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
