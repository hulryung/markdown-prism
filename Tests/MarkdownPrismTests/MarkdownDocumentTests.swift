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
}
