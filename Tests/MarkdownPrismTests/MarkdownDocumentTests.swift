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

    // MARK: - Telling our own saves apart from someone else's

    private func scratchFile(_ contents: String, encoding: String.Encoding = .utf8) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown-prism-\(UUID().uuidString).md")
        try XCTUnwrap(contents.data(using: encoding)).write(to: url)
        return url
    }

    /// The watcher cannot tell the app's own write from anyone else's; what
    /// landed can.
    func test_fileHolds_isTrueWhenTheFileAlreadySaysWhatIsOnScreen() throws {
        let url = try scratchFile("# Spec\n\nBody.\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(MarkdownDocument.file(at: url, holds: "# Spec\n\nBody.\n"))
    }

    func test_fileHolds_isFalseWhenSomethingElseChangedIt() throws {
        let url = try scratchFile("# Spec\n\nEdited by something else.\n")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertFalse(MarkdownDocument.file(at: url, holds: "# Spec\n\nBody.\n"))
    }

    /// Unreadable is not "unchanged": the caller has a path for that, and
    /// answering true here would silently swallow a reload.
    func test_fileHolds_isFalseWhenTheFileCannotBeRead() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("markdown-prism-gone-\(UUID().uuidString).md")

        XCTAssertFalse(MarkdownDocument.file(at: missing, holds: ""))
    }

    /// Saves reproduce the encoding a file was read in, so the comparison has to
    /// decode rather than compare bytes — otherwise every save of a UTF-16 file
    /// would look like an outside change.
    func test_fileHolds_comparesTextRatherThanBytes() throws {
        let url = try scratchFile("# Spec\n\nBody.\n", encoding: .utf16)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(MarkdownDocument.file(at: url, holds: "# Spec\n\nBody.\n"))
    }
}
