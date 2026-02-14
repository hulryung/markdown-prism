import SwiftUI

class OpenFileState: ObservableObject {
    @Published var pendingURL: URL?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let openFileState = OpenFileState()

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        openFileState.pendingURL = url
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
    @FocusedValue(\.saveFileAction) var saveFileAction
    @FocusedValue(\.saveAsFileAction) var saveAsFileAction

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
    }
}
