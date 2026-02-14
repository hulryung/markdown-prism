import Foundation

struct MarkdownDocument {
    let text: String
    let fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.text = try String(contentsOf: fileURL, encoding: .utf8)
    }
}
