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

        // Prompt to set as default Markdown app on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            DefaultAppHelper.promptIfFirstLaunch()
        }
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
        DocumentGroup(newDocument: MarkdownFileDocument()) { file in
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
