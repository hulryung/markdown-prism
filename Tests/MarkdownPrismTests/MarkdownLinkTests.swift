import XCTest
@testable import MarkdownPrism

final class MarkdownLinkTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/notes/project/docs/Start.md")

    func test_relativeMarkdownLinks_resolveAgainstTheCurrentDocument() {
        let links = [
            "Next.md": "/notes/project/docs/Next.md",
            "../README.md": "/notes/project/README.md",
            "./nested/../Next.MARKDOWN": "/notes/project/docs/Next.MARKDOWN",
            "nested/Guide.md": "/notes/project/docs/nested/Guide.md"
        ]
        for (href, path) in links {
            XCTAssertEqual(MarkdownLink.destination(for: href, relativeTo: source),
                           .document(URL(fileURLWithPath: path)), href)
        }
    }

    func test_escapedFilenames_decodeOnceWithoutLosingLiteralPathCharacters() {
        let links = [
            "Next%20Steps.md": "Next Steps.md",
            "Next%20Steps.md#details": "Next Steps.md",
            "Next.md?view=1#details": "Next.md",
            "%ED%95%9C%EA%B8%80.md": "한글.md",
            "file%23name.md": "file#name.md",
            "file%2520name.md": "file%20name.md"
        ]
        for (href, name) in links {
            XCTAssertEqual(MarkdownLink.destination(for: href, relativeTo: source),
                           .document(source.deletingLastPathComponent().appendingPathComponent(name)), href)
        }
    }

    func test_externalLinks_stayExternalEvenWhenTheyEndInMarkdown() throws {
        for href in ["https://example.com/README.md", "HTTP://example.com/", "mailto:test@example.com"] {
            XCTAssertEqual(MarkdownLink.destination(for: href, relativeTo: source),
                           .external(try XCTUnwrap(URL(string: href))))
        }
    }

    func test_unsupportedLinksAndLocalAnchors_doNotOpenDocuments() {
        for href in ["", "#heading", "diagram.png", "other.pdf", "javascript:Next.md",
                     "custom:Next.md", "//server/share/Next.md", "file://server/share/Next.md"] {
            XCTAssertNil(MarkdownLink.destination(for: href, relativeTo: source), href)
        }
    }

    func test_absoluteLocalFileURL_doesNotNeedASavedSourceDocument() {
        XCTAssertEqual(MarkdownLink.destination(for: "file:///notes/Next%20Steps.md", relativeTo: nil),
                       .document(URL(fileURLWithPath: "/notes/Next Steps.md")))
        XCTAssertNil(MarkdownLink.destination(for: "Next.md", relativeTo: nil))
    }
}
