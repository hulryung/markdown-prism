import XCTest
@testable import MarkdownPrism

@MainActor
final class PreviewLinkTests: XCTestCase {
    func test_unreadableOrMissingLink_reachesDocumentOpeningInsteadOfSilentlyDisappearing() {
        let coordinator = PreviewView.Coordinator()
        coordinator.fileURL = URL(fileURLWithPath: "/ungranted-folder/Start.md")
        let opened = expectation(description: "document open attempted")
        coordinator.onOpenFile = { url in
            XCTAssertEqual(url.path, "/ungranted-folder/Next.md")
            opened.fulfill()
        }

        coordinator.handleLinkClick(href: "Next.md")

        wait(for: [opened], timeout: 1)
    }

    func test_encodedLinkWithFragment_opensTheDocumentPath() {
        let coordinator = PreviewView.Coordinator()
        coordinator.fileURL = URL(fileURLWithPath: "/ungranted-folder/Start.md")
        let opened = expectation(description: "encoded document open attempted")
        coordinator.onOpenFile = { url in
            XCTAssertEqual(url.path, "/ungranted-folder/Next Steps.md")
            XCTAssertNil(url.fragment)
            opened.fulfill()
        }

        coordinator.handleLinkClick(href: "Next%20Steps.md#details")

        wait(for: [opened], timeout: 1)
    }
}
