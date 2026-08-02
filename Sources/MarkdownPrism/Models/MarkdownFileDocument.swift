import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared as an imported type in Info.plist.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// The document behind each editor window.
///
/// Being a `FileDocument` is what hands the app the whole document apparatus —
/// open, save, save as, revert, autosave, versions, per-window dirty state,
/// window tabs, and an Open Recent menu whose entries keep working across
/// launches inside the sandbox.
struct MarkdownFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [.markdown] }

    var text: String
    /// How the file was encoded when it was read, so saving reproduces it
    /// rather than quietly rewriting every document as UTF-8.
    var format: TextFileFormat

    init(text: String = "", format: TextFileFormat = .utf8) {
        self.text = text
        self.format = format
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        (text, format) = try MarkdownDocument.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // If the text has grown characters the original encoding cannot hold,
        // fall back to UTF-8 instead of refusing to save.
        guard let data = format.encode(text) ?? TextFileFormat.utf8.encode(text) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
