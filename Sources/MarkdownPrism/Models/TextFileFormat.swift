import Foundation

/// How a file's bytes were laid out when it was read, so saving can reproduce
/// it instead of silently rewriting the file as UTF-8.
struct TextFileFormat: Equatable {
    var encoding: String.Encoding
    /// The exact byte order mark the file started with, if any. Foundation does
    /// not re-emit one for the explicit UTF-16/32 encodings, so it is kept
    /// verbatim rather than inferred back from the encoding.
    var byteOrderMark: Data?

    static let utf8 = TextFileFormat(encoding: .utf8, byteOrderMark: nil)

    /// Encodes `text` in this format.
    ///
    /// Returns nil when the encoding cannot represent the text — a Latin-1
    /// document that has since gained an emoji, say. Callers fall back to UTF-8
    /// rather than refuse the save.
    func encode(_ text: String) -> Data? {
        guard let body = text.data(using: encoding, allowLossyConversion: false) else {
            return nil
        }
        guard let byteOrderMark else { return body }
        return byteOrderMark + body
    }
}
