import SwiftUI

@main
struct MarkdownPrismApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
