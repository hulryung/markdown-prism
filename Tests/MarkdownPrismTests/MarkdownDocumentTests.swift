import XCTest
@testable import MarkdownPrism

final class MarkdownDocumentTests: XCTestCase {
    func testLoadsUTF8Markdown() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        let expected = "# 제목\n\nUTF-8 text"
        try expected.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try MarkdownDocument(fileURL: url)
        XCTAssertEqual(document.text, expected)
    }

    func testLoadsUTF16Markdown() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        let expected = "# Title\n\nUTF-16 text"
        try expected.write(to: url, atomically: true, encoding: .utf16)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try MarkdownDocument(fileURL: url)
        XCTAssertEqual(document.text, expected)
    }

    func testNonexistentURLThrowsFileReadError() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        XCTAssertThrowsError(try MarkdownDocument(fileURL: url)) { error in
            XCTAssertFalse(error is MarkdownDocument.Error)
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSCocoaErrorDomain)
        }
    }

    func testLoadsLatin1FallbackWithoutBOM() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try MarkdownDocument(fileURL: url)
        XCTAssertEqual(document.text, "café")
    }

    func testLoadsEvenLengthLatin1FallbackWithoutBOM() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        try Data([0x63, 0x61, 0x66, 0xE9, 0x21, 0x21]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try MarkdownDocument(fileURL: url)
        XCTAssertEqual(document.text, "café!!")
    }

    func testEmptyFileYieldsEmptyText() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try MarkdownDocument(fileURL: url)
        XCTAssertEqual(document.text, "")
    }

    func testLoadsUTF8WithBOMAndStripsIt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        let bom = Data([0xEF, 0xBB, 0xBF])
        let content = "# Title\n\nUTF-8 with BOM"
        try (bom + Data(content.utf8)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try MarkdownDocument(fileURL: url)
        XCTAssertEqual(document.text, content)
        XCTAssertFalse(document.text.hasPrefix("\u{FEFF}"))
    }

    func testLoadsUTF16LEWithBOMAndNoLeadingBOMCharacter() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        let bom = Data([0xFF, 0xFE])
        let expected = "# Title\n\nUTF-16 LE text"
        let body = expected.data(using: .utf16LittleEndian)!
        try (bom + body).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try MarkdownDocument(fileURL: url)
        XCTAssertEqual(document.text, expected)
        XCTAssertFalse(document.text.hasPrefix("\u{FEFF}"))
    }
}
