import SwiftUI

class OpenFileState: ObservableObject {
    @Published var pendingURL: URL?
    @Published var isModified = false
    var saveHandler: (() -> Bool)?
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let openFileState = OpenFileState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app appears as a regular app with Dock icon and menu bar
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Load app icon from bundled resource (xcassets not available in SPM builds)
        #if SWIFT_PACKAGE
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Resources"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        #endif

        // Open file passed as command-line argument
        let args = ProcessInfo.processInfo.arguments
        if args.count > 1 {
            let path = args[1]
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                openFileState.pendingURL = url
            }
        }

        // Set window delegate after SwiftUI creates the window
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                window.delegate = self
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        openFileState.pendingURL = url
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmSaveIfNeeded()
    }

    // MARK: - App Termination

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        confirmSaveIfNeeded() ? .terminateNow : .terminateCancel
    }

    private func confirmSaveIfNeeded() -> Bool {
        guard openFileState.isModified else { return true }

        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Do you want to save your changes before closing?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return openFileState.saveHandler?() ?? false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}

@main
struct MarkdownPrismApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.openFileState)
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            FileCommands()
        }
    }
}

struct FileCommands: Commands {
    @FocusedValue(\.newFileAction) var newFileAction
    @FocusedValue(\.openFileAction) var openFileAction
    @FocusedValue(\.openRecentAction) var openRecentAction
    @FocusedValue(\.saveFileAction) var saveFileAction
    @FocusedValue(\.saveAsFileAction) var saveAsFileAction
    @FocusedValue(\.zoomInAction) var zoomInAction
    @FocusedValue(\.zoomOutAction) var zoomOutAction
    @FocusedValue(\.resetZoomAction) var resetZoomAction
    @FocusedValue(\.findAction) var findAction
    @FocusedValue(\.findNextAction) var findNextAction
    @FocusedValue(\.findPreviousAction) var findPreviousAction
    @FocusedValue(\.dismissFindAction) var dismissFindAction
    @FocusedValue(\.showReplaceAction) var showReplaceAction
    @ObservedObject private var recentDocuments = RecentDocumentsManager.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                newFileAction?()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open...") {
                openFileAction?()
            }
            .keyboardShortcut("o", modifiers: .command)

            Menu("Open Recent") {
                ForEach(recentDocuments.recentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        openRecentAction?(url)
                    }
                }
                if !recentDocuments.recentURLs.isEmpty {
                    Divider()
                }
                Button("Clear Menu") {
                    recentDocuments.clear()
                }
                .disabled(recentDocuments.recentURLs.isEmpty)
            }
        }

        CommandGroup(after: .newItem) {
            Button("Save") {
                saveFileAction?()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(saveFileAction == nil)

            Button("Save As...") {
                saveAsFileAction?()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Button("Zoom In") {
                zoomInAction?()
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(zoomInAction == nil)

            Button("Zoom Out") {
                zoomOutAction?()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(zoomOutAction == nil)

            Button("Actual Size") {
                resetZoomAction?()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(resetZoomAction == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") {
                findAction?()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find Next") {
                findNextAction?()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(findNextAction == nil)

            Button("Find Previous") {
                findPreviousAction?()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(findPreviousAction == nil)

            Button("Find & Replace…") {
                showReplaceAction?()
            }
            .keyboardShortcut("f", modifiers: [.command, .option])

            Button("Dismiss Find") {
                dismissFindAction?()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(dismissFindAction == nil)
        }
    }
}
