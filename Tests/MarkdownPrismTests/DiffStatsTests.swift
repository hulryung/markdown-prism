import XCTest
@testable import MarkdownPrism

final class DiffStatsTests: XCTestCase {
    func test_between_identicalText_countsNothing() {
        let stats = DiffStats.between("# Spec\n\nBody.\n", "# Spec\n\nBody.\n")
        XCTAssertEqual(stats, .none)
        XCTAssertTrue(stats.isEmpty)
    }

    func test_between_appendedLines_countsAdditionsOnly() {
        let stats = DiffStats.between("one\ntwo\n", "one\ntwo\nthree\nfour\n")
        XCTAssertEqual(stats, DiffStats(additions: 2, deletions: 0))
    }

    func test_between_removedLines_countsDeletionsOnly() {
        let stats = DiffStats.between("one\ntwo\nthree\n", "one\n")
        XCTAssertEqual(stats, DiffStats(additions: 0, deletions: 2))
    }

    func test_between_replacedLine_countsBothSides() {
        let stats = DiffStats.between("one\ntwo\nthree\n", "one\nTWO\nthree\n")
        XCTAssertEqual(stats, DiffStats(additions: 1, deletions: 1))
    }

    func test_between_editInTheMiddleOfALongDocument_countsOnlyThatEdit() {
        let old = (1...500).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let new = old.replacingOccurrences(of: "line 250", with: "line 250 edited")
        XCTAssertEqual(DiffStats.between(old, new), DiffStats(additions: 1, deletions: 1))
    }

    func test_between_emptyBaseline_countsTheWholeDocumentAsAdded() {
        XCTAssertEqual(DiffStats.between("", "one\ntwo\n"), DiffStats(additions: 2, deletions: 0))
    }

    func test_between_emptyNewText_countsTheWholeDocumentAsDeleted() {
        XCTAssertEqual(DiffStats.between("one\ntwo\n", ""), DiffStats(additions: 0, deletions: 2))
    }

    /// Interning each side's lines separately would give the first line of each
    /// the same identifier and call two different documents equal.
    func test_between_documentsSharingNoLines_doesNotReportThemEqual() {
        XCTAssertEqual(DiffStats.between("a\n", "b\n"), DiffStats(additions: 1, deletions: 1))
        XCTAssertEqual(
            DiffStats.between("alpha\nbravo\n", "charlie\ndelta\n"),
            DiffStats(additions: 2, deletions: 2)
        )
    }

    func test_between_textWithoutATrailingNewline_countsTheLastLineOnce() {
        XCTAssertEqual(DiffStats.between("one\ntwo", "one\ntwo\n"), .none)
        XCTAssertEqual(DiffStats.between("one", "one\ntwo"), DiffStats(additions: 1, deletions: 0))
    }

    func test_between_whollyDifferentDocuments_countsEveryLine() {
        let old = (1...40).map { "old \($0)" }.joined(separator: "\n") + "\n"
        let new = (1...25).map { "new \($0)" }.joined(separator: "\n") + "\n"
        XCTAssertEqual(DiffStats.between(old, new), DiffStats(additions: 25, deletions: 40))
    }
}
