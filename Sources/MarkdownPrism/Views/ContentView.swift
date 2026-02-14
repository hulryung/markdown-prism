import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var markdownText = "# Markdown Prism\n\nOpen a `.md` file to preview **GFM**, `$x^2$`, and `mermaid` blocks."
    @State private var fileURL: URL?

    var body: some View {
        PreviewView(markdown: markdownText)
            .frame(minWidth: 720, minHeight: 480)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: openFile) {
                        Label("Open", systemImage: "doc")
                    }
                }
            }
            .navigationTitle(fileURL?.lastPathComponent ?? "Markdown Prism")
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
            }
    }

    private func openFile() {
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

    private func loadFile(_ url: URL) {
        do {
            let document = try MarkdownDocument(fileURL: url)
            markdownText = document.text
            fileURL = url
        } catch {
            markdownText = "Error loading file: \(error.localizedDescription)"
        }
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
