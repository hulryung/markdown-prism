import XCTest
@testable import MarkdownPrism

final class TextFileFormatTests: XCTestCase {
    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Round trips

    func test_utf8WithoutBOM_roundTripsByteForByte() throws {
        let original = Data("# Hello\n\nBody\n".utf8)
        let url = try temporaryFile(original)

        let document = try MarkdownDocument(fileURL: url)
        let written = try XCTUnwrap(document.format.encode(document.text))

        XCTAssertEqual(document.format.encoding, .utf8)
        XCTAssertNil(document.format.byteOrderMark)
        XCTAssertEqual(written, original)
    }

    func test_utf8WithBOM_keepsItsBOM() throws {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let original = bom + Data("# Hello\n".utf8)
        let url = try temporaryFile(original)

        let document = try MarkdownDocument(fileURL: url)
        let written = try XCTUnwrap(document.format.encode(document.text))

        XCTAssertEqual(document.text, "# Hello\n", "the BOM should not leak into the text")
        XCTAssertEqual(written, original)
    }

    func test_utf16LittleEndian_roundTripsWithItsBOM() throws {
        let bom = Data([0xFF, 0xFE])
        let original = bom + Data("# Hello\n".data(using: .utf16LittleEndian)!)
        let url = try temporaryFile(original)

        let document = try MarkdownDocument(fileURL: url)
        let written = try XCTUnwrap(document.format.encode(document.text))

        XCTAssertEqual(document.format.encoding, .utf16LittleEndian)
        XCTAssertEqual(document.text, "# Hello\n")
        XCTAssertEqual(written, original)
    }

    func test_utf16BigEndian_roundTripsWithItsBOM() throws {
        let bom = Data([0xFE, 0xFF])
        let original = bom + Data("제목\n".data(using: .utf16BigEndian)!)
        let url = try temporaryFile(original)

        let document = try MarkdownDocument(fileURL: url)
        let written = try XCTUnwrap(document.format.encode(document.text))

        XCTAssertEqual(document.format.encoding, .utf16BigEndian)
        XCTAssertEqual(document.text, "제목\n")
        XCTAssertEqual(written, original)
    }

    func test_latin1_roundTripsWithoutBecomingUTF8() throws {
        // 0xE9 is é in Latin-1 and invalid on its own in UTF-8, so the reader
        // must fall through to the Latin-1 branch.
        let original = Data([0x63, 0x61, 0x66, 0xE9, 0x0A])
        let url = try temporaryFile(original)

        let document = try MarkdownDocument(fileURL: url)
        let written = try XCTUnwrap(document.format.encode(document.text))

        XCTAssertEqual(document.format.encoding, .isoLatin1)
        XCTAssertEqual(document.text, "café\n")
        XCTAssertEqual(written, original)
    }

    // MARK: - Edits

    func test_editedText_isWrittenInTheOriginalEncoding() throws {
        let bom = Data([0xFF, 0xFE])
        let url = try temporaryFile(bom + Data("one\n".data(using: .utf16LittleEndian)!))

        let document = try MarkdownDocument(fileURL: url)
        let edited = document.text + "two\n"
        let written = try XCTUnwrap(document.format.encode(edited))

        XCTAssertEqual(written, bom + Data("one\ntwo\n".data(using: .utf16LittleEndian)!))
    }

    func test_encode_returnsNilWhenTheEncodingCannotHoldTheText() {
        let latin1 = TextFileFormat(encoding: .isoLatin1, byteOrderMark: nil)

        XCTAssertNotNil(latin1.encode("café"))
        XCTAssertNil(latin1.encode("emoji 😀"), "caller should fall back to UTF-8")
    }
}
