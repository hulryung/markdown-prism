import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load app icon from bundled resource (xcassets not available in SPM builds)
        #if SWIFT_PACKAGE
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Resources"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        #endif

        // Created here, before SwiftUI gets the chance to put its Open panel on
        // screen. AppKit says outright whether the launch came with a document,
        // so this needs no delay and no guessing from document counts.
        let isDefaultLaunch = notification
            .userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch {
            openWelcomeDocument()
        }

        // Prompt to set as default Markdown app on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            DefaultAppHelper.promptIfFirstLaunch()
        }
    }

    /// Reopening — the Dock icon, or opening the app while it is already
    /// running — with every window closed otherwise lands on the Open panel.
    /// A new empty document is the more useful answer; the welcome sample
    /// belongs to a cold launch only.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        NSDocumentController.shared.newDocument(nil)
        return false
    }

    /// SwiftUI's DocumentGroup presents the Open panel when the app launches
    /// with nothing to open, and never consults the AppKit delegate methods for
    /// untitled files. Creating the document here is what brings the app up on
    /// the welcome document instead.
    private func openWelcomeDocument() {
        guard NSDocumentController.shared.documents.isEmpty else { return }
        WelcomeDocument.armForNextDocument()
        NSDocumentController.shared.newDocument(nil)
    }
}

@main
struct MarkdownPrismApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // New, Open, Open Recent, Save, Save As, Duplicate, Rename, Revert, the
        // unsaved-changes prompts, window tabs and per-document dirty state all
        // come from the document architecture; only the commands below are the
        // app's own.
        DocumentGroup(newDocument: WelcomeDocument.makeDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Set as Default Markdown App...") {
                    DefaultAppHelper.setAsDefault()
                }
            }
            EditorCommands()
        }
    }
}

struct EditorCommands: Commands {
    @FocusedValue(\.zoomInAction) var zoomInAction
    @FocusedValue(\.zoomOutAction) var zoomOutAction
    @FocusedValue(\.resetZoomAction) var resetZoomAction
    @FocusedValue(\.findAction) var findAction
    @FocusedValue(\.findNextAction) var findNextAction
    @FocusedValue(\.findPreviousAction) var findPreviousAction
    @FocusedValue(\.dismissFindAction) var dismissFindAction
    @FocusedValue(\.showReplaceAction) var showReplaceAction

    var body: some Commands {
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
            .disabled(findAction == nil)

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
            .disabled(showReplaceAction == nil)

            Button("Dismiss Find") {
                dismissFindAction?()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(dismissFindAction == nil)
        }
    }
}
