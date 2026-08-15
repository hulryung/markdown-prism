import Foundation

struct MarkdownDocument {
    enum Error: Swift.Error {
        case unsupportedEncoding
    }

    let text: String
    let fileURL: URL
    /// How the file was encoded on disk, so a later save can write it back the
    /// same way.
    let format: TextFileFormat

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        (text, format) = try Self.decode(try Data(contentsOf: fileURL))
    }

    /// Whether the file at `url` already holds `text`.
    ///
    /// A save the app just made looks exactly like a change from outside — the
    /// same write, the same event — and autosaving in place means that happens
    /// while the reader types, not only when they ask to save. What tells the
    /// two apart is what landed: if the file already says what is on screen,
    /// there is nothing to reload and nothing worth asking about.
    ///
    /// An unreadable file answers false, which sends the caller down its usual
    /// path rather than inventing an outcome here.
    static func file(at url: URL, holds text: String) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decode(data) else { return false }
        return decoded.text == text
    }

    /// Decodes file bytes, reporting the format so a save can reproduce them.
    static func decode(_ data: Data) throws -> (text: String, format: TextFileFormat) {
        if let utf8Text = String(data: data, encoding: .utf8) {
            return (
                strippingLeadingBOM(from: utf8Text),
                TextFileFormat(encoding: .utf8, byteOrderMark: utf8ByteOrderMark(for: data))
            )
        }

        if let (bomEncoding, bom) = bomEncoding(for: data) {
            guard let decoded = String(data: data, encoding: bomEncoding) else {
                throw Error.unsupportedEncoding
            }
            return (
                strippingLeadingBOM(from: decoded),
                TextFileFormat(encoding: bomEncoding, byteOrderMark: bom)
            )
        }

        guard let decoded = String(data: data, encoding: .isoLatin1) else {
            throw Error.unsupportedEncoding
        }
        return (decoded, TextFileFormat(encoding: .isoLatin1, byteOrderMark: nil))
    }

    private static func utf8ByteOrderMark(for data: Data) -> Data? {
        let bom = Data([0xEF, 0xBB, 0xBF])
        return data.starts(with: bom) ? bom : nil
    }

    private static func bomEncoding(for data: Data) -> (String.Encoding, Data)? {
        let bytes = [UInt8](data.prefix(4))

        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return (.utf32LittleEndian, Data([0xFF, 0xFE, 0x00, 0x00]))
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return (.utf32BigEndian, Data([0x00, 0x00, 0xFE, 0xFF]))
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return (.utf16LittleEndian, Data([0xFF, 0xFE]))
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return (.utf16BigEndian, Data([0xFE, 0xFF]))
        }
        return nil
    }

    private static func strippingLeadingBOM(from string: String) -> String {
        guard string.first == "\u{FEFF}" else { return string }
        return String(string.dropFirst())
    }
}
