import XCTest
@testable import MarkdownPrism

final class RecentDocumentsManagerTests: XCTestCase {
    private let suiteName = "RecentDocumentsManagerTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAddURLPutsNewestFirst() {
        let manager = RecentDocumentsManager(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/first.md")
        let second = URL(fileURLWithPath: "/tmp/second.md")

        manager.addURL(first)
        manager.addURL(second)

        XCTAssertEqual(manager.recentURLs.first, second)
        XCTAssertEqual(manager.recentURLs, [second, first])
    }

    func testReaddingExistingURLMovesToFrontWithoutDuplicating() {
        let manager = RecentDocumentsManager(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/first.md")
        let second = URL(fileURLWithPath: "/tmp/second.md")

        manager.addURL(first)
        manager.addURL(second)
        manager.addURL(first)

        XCTAssertEqual(manager.recentURLs, [first, second])
    }

    func testAddingEleventhURLDropsOldest() {
        let manager = RecentDocumentsManager(defaults: defaults)
        let urls = (0..<11).map { URL(fileURLWithPath: "/tmp/file\($0).md") }

        for url in urls {
            manager.addURL(url)
        }

        XCTAssertEqual(manager.recentURLs.count, 10)
        XCTAssertEqual(manager.recentURLs.first, urls.last)
        XCTAssertFalse(manager.recentURLs.contains(urls[0]))
    }

    func testClearEmptiesListAndPersists() {
        let manager = RecentDocumentsManager(defaults: defaults)
        manager.addURL(URL(fileURLWithPath: "/tmp/first.md"))

        manager.clear()

        XCTAssertTrue(manager.recentURLs.isEmpty)

        let reloaded = RecentDocumentsManager(defaults: defaults)
        XCTAssertTrue(reloaded.recentURLs.isEmpty)
    }

    func testLoadDropsMissingFilesAndPreservesOrderOfSurvivors() throws {
        let survivorA = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        let survivorB = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try "a".write(to: survivorA, atomically: true, encoding: .utf8)
        try "b".write(to: survivorB, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: survivorA)
            try? FileManager.default.removeItem(at: survivorB)
        }

        let deletedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")

        defaults.set([survivorA.path, deletedURL.path, survivorB.path], forKey: "recentDocuments")

        let manager = RecentDocumentsManager(defaults: defaults)

        XCTAssertEqual(manager.recentURLs, [survivorA, survivorB])
    }
}
