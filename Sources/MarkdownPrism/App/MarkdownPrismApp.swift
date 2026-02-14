import SwiftUI

@main
struct MarkdownPrismApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
