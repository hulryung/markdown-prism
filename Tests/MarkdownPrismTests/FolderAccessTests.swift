import XCTest
@testable import MarkdownPrism

@MainActor
final class FolderAccessTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/notes/project/docs/Start.md")

    func test_siblingAndNestedLinks_suggestTheCurrentDocumentFolder() {
        let purpose = FolderAccess.Purpose.linkedDocument(source: source)
        for path in ["/notes/project/docs/Next.md", "/notes/project/docs/nested/Next.md"] {
            XCTAssertEqual(purpose.suggestedFolder(containing: URL(fileURLWithPath: path)),
                           source.deletingLastPathComponent())
        }
    }

    func test_parentLink_suggestsTheParentFolder() {
        let purpose = FolderAccess.Purpose.linkedDocument(source: source)
        XCTAssertEqual(purpose.suggestedFolder(containing: URL(fileURLWithPath: "/notes/project/README.md")),
                       URL(fileURLWithPath: "/notes/project", isDirectory: true))
    }

    func test_unrelatedFolderWithSimilarPrefix_isNotTreatedAsAlreadyContainingTheTarget() {
        let purpose = FolderAccess.Purpose.linkedDocument(source: source)
        XCTAssertEqual(purpose.suggestedFolder(containing: URL(fileURLWithPath: "/notes/project/docs-other/Next.md")),
                       URL(fileURLWithPath: "/notes/project/docs-other", isDirectory: true))
    }

    func test_noSource_suggestsTheTargetFolder() {
        XCTAssertEqual(FolderAccess.Purpose.linkedDocument(source: nil).suggestedFolder(containing: source),
                       source.deletingLastPathComponent())
    }
}
