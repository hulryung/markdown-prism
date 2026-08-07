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

        openComparisonIfRequested()

        // The saved theme has to land before the first window draws, or the app
        // flashes the system appearance and then corrects itself.
        AppSettings.shared.applyAppearance()

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

    // MARK: - Comparisons handed over by git difftool

    /// AppKit routes opened files through the delegate only when it answers to
    /// this, so answering no outside a comparison leaves the document machinery
    /// — Finder, Open Recent, drag to the Dock — running exactly as it did.
    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(NSApplicationDelegate.application(_:openFiles:)) {
            return DiffLaunch.isRequested()
        }
        return super.responds(to: selector)
    }

    /// Only reached for a launch that asked for a comparison; see above.
    ///
    /// The delivery is answered and discarded. A document-based app is handed
    /// exactly one of the two files, whichever LaunchServices picks, and neither
    /// belongs in a document window — they are git's temporary copies. The two
    /// sides are read from the arguments instead, which name both.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        sender.reply(toOpenOrPrint: .success)
    }
    /// A comparison window is the whole reason this launch happened, so closing
    /// it ends the run — which is also what releases the `open -W` that git is
    /// waiting on before it moves to the next file.
    ///
    /// Not before that window exists, though. A comparison opens no document, so
    /// between launch and the window appearing the app has none at all, and
    /// would otherwise read that as nothing left to do and quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        DiffLaunch.isRequested() && ComparisonWindow.hasShown
    }

    /// Shows the comparison the arguments describe, once the files can be read.
    ///
    /// Being passed to `open` is what grants them, but the grant is not in place
    /// the moment the app comes up — the same read fails here and succeeds a
    /// fraction of a second later. The wait is a run-loop hop rather than a
    /// sleep or a nested run loop: the first blocks the delivery being waited
    /// on, and the second lets the app terminate out from under this.
    @MainActor
    private func openComparisonIfRequested(attempt: Int = 0) {
        guard DiffLaunch.isRequested() else { return }

        if let comparison = DiffLaunch.comparison(read: { try? MarkdownDocument(fileURL: $0).text }) {
            ComparisonWindow.show(comparison)
            return
        }

        // Measured at well under 100ms; the ceiling is for a loaded machine.
        guard attempt < 40 else {
            let alert = NSAlert()
            alert.messageText = "Could not read the versions to compare"
            alert.informativeText = """
                Git extracts the two versions to temporary files and removes them \
                when the tool exits. Check the difftool command in your Git config.
                """
            alert.alertStyle = .warning
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.openComparisonIfRequested(attempt: attempt + 1)
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

        Settings {
            SettingsView(settings: AppSettings.shared)
        }
    }
}

struct EditorCommands: Commands {
    @FocusedValue(\.diffCommand) var diffCommand
    @FocusedValue(\.nextChangeAction) var nextChangeAction
    @FocusedValue(\.previousChangeAction) var previousChangeAction
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
            Menu("Show Changes") {
                Picker("Compare With", selection: baselineBinding) {
                    ForEach(DiffBaseline.menuOptions) { baseline in
                        Text(baseline.label).tag(baseline)
                    }
                }
                .pickerStyle(.inline)
            }
            .disabled(diffCommand == nil)

            // The one comparison worth a shortcut: what changed since the last
            // commit, which is what someone reviewing an agent's edits wants.
            Button("Show Changes Since Last Commit") {
                guard let diffCommand else { return }
                diffCommand.select(diffCommand.current == .lastCommit ? .off : .lastCommit)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(diffCommand == nil)

            // Stepping between changes is what makes a long document readable;
            // both are disabled unless there is something to step through.
            Button("Next Change") {
                nextChangeAction?()
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(nextChangeAction == nil)

            Button("Previous Change") {
                previousChangeAction?()
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(previousChangeAction == nil)

            Divider()
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

    /// Reads and writes the focused window's comparison. With no document
    /// focused the menu is disabled, so the setter has nothing to reach.
    private var baselineBinding: Binding<DiffBaseline> {
        Binding(
            get: { diffCommand?.current ?? .off },
            set: { diffCommand?.select($0) }
        )
    }
}
