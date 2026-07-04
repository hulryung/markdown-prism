import Foundation

struct MarkdownDocument {
    enum Error: Swift.Error {
        case unsupportedEncoding
    }

    let text: String
    let fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL

        let data = try Data(contentsOf: fileURL)

        if let utf8Text = String(data: data, encoding: .utf8) {
            text = Self.strippingLeadingBOM(from: utf8Text)
            return
        }

        if let bomEncoding = Self.bomEncoding(for: data) {
            guard let decoded = String(data: data, encoding: bomEncoding) else {
                throw Error.unsupportedEncoding
            }
            text = Self.strippingLeadingBOM(from: decoded)
            return
        }

        guard let decoded = String(data: data, encoding: .isoLatin1) else {
            throw Error.unsupportedEncoding
        }
        text = decoded
    }

    private static func bomEncoding(for data: Data) -> String.Encoding? {
        let bytes = [UInt8](data.prefix(4))

        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return .utf32LittleEndian
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return .utf32BigEndian
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return .utf16LittleEndian
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return .utf16BigEndian
        }
        return nil
    }

    private static func strippingLeadingBOM(from string: String) -> String {
        guard string.first == "\u{FEFF}" else { return string }
        return String(string.dropFirst())
    }
}
