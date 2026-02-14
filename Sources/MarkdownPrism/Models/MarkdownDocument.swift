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
        let fallbackEncodings: [String.Encoding] = [
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .utf32,
            .ascii,
            .isoLatin1
        ]

        if let utf8Text = String(data: data, encoding: .utf8) {
            text = utf8Text
            return
        }

        for encoding in fallbackEncodings {
            if let decoded = String(data: data, encoding: encoding) {
                text = decoded
                return
            }
        }

        throw Error.unsupportedEncoding
    }
}
