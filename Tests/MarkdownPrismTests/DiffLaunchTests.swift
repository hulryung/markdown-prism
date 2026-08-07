import XCTest
@testable import MarkdownPrism

/// Covers the contract `git difftool` is configured against: which launch counts
/// as a comparison, and where the two sides come from.
@MainActor
final class DiffLaunchTests: XCTestCase {
    private let baselinePath = "/var/folders/x/git-blob-AbC123/spec.md"
    private let currentPath = "/Users/someone/project/spec.md"

    private func arguments(
        diff: Bool = true,
        baseline: String? = nil,
        current: String? = nil
    ) -> [String] {
        var arguments = ["MarkdownPrism"]
        if diff { arguments.append("--diff") }
        if let baseline { arguments += ["--baseline", baseline] }
        if let current { arguments += ["--current", current] }
        return arguments
    }

    // MARK: - Recognising the launch

    func test_isRequested_onlyWhenTheFlagIsPresent() {
        XCTAssertTrue(DiffLaunch.isRequested(in: arguments()))
        XCTAssertFalse(DiffLaunch.isRequested(in: ["MarkdownPrism"]))
        XCTAssertFalse(
            DiffLaunch.isRequested(in: arguments(diff: false, baseline: baselinePath)),
            "naming a baseline is not on its own a request to compare"
        )
    }

    func test_declaredPaths_readTheValueAfterEachFlag() {
        let arguments = arguments(baseline: baselinePath, current: currentPath)

        XCTAssertEqual(DiffLaunch.declaredBaselinePath(in: arguments), baselinePath)
        XCTAssertEqual(DiffLaunch.declaredCurrentPath(in: arguments), currentPath)
        XCTAssertNil(DiffLaunch.declaredBaselinePath(in: ["MarkdownPrism", "--diff"]))
        XCTAssertNil(
            DiffLaunch.declaredBaselinePath(in: ["MarkdownPrism", "--diff", "--baseline"]),
            "a flag with nothing after it names nothing"
        )
    }

    // MARK: - Building the comparison

    /// The arguments name both sides, so which file LaunchServices happens to
    /// deliver — and in which order — never comes into it.
    func test_comparison_takesBothSidesFromTheArguments() throws {
        let comparison = try XCTUnwrap(
            DiffLaunch.comparison(in: arguments(baseline: baselinePath, current: currentPath)) { url in
                url.path == self.baselinePath ? "committed text\n" : "working text\n"
            }
        )

        XCTAssertEqual(comparison.baseline, "committed text\n")
        XCTAssertEqual(comparison.current, "working text\n")
        XCTAssertEqual(comparison.name, "spec.md")
    }

    /// git names the working-tree file relative to the repository, and the app's
    /// own working directory is its sandbox container — so a relative side is
    /// meaningless without being told where it belongs.
    func test_comparison_resolvesARelativeCurrentAgainstTheRepository() throws {
        let arguments = arguments(baseline: baselinePath, current: "docs/spec.md")
            + ["--directory", "/Users/someone/project"]

        let comparison = try XCTUnwrap(DiffLaunch.comparison(in: arguments) { _ in "text\n" })
        XCTAssertEqual(comparison.name, "spec.md")
    }

    /// Comparing two commits gives two absolute temporary paths, which the
    /// repository directory must not be prepended to.
    func test_comparison_leavesAnAbsoluteCurrentAlone() throws {
        let arguments = arguments(baseline: baselinePath, current: "/var/folders/x/git-blob-Zz9/spec.md")
            + ["--directory", "/Users/someone/project"]

        let comparison = try XCTUnwrap(DiffLaunch.comparison(in: arguments) { _ in "text\n" })
        XCTAssertEqual(comparison.name, "spec.md")
    }

    func test_comparison_isNilWithoutEverythingItNeeds() {
        let read: (URL) -> String? = { _ in "text\n" }

        XCTAssertNil(
            DiffLaunch.comparison(in: arguments(diff: false, baseline: baselinePath, current: currentPath), read: read),
            "without the flag this is an ordinary launch"
        )
        XCTAssertNil(
            DiffLaunch.comparison(in: arguments(current: currentPath), read: read),
            "no baseline to compare against"
        )
        XCTAssertNil(
            DiffLaunch.comparison(in: arguments(baseline: baselinePath), read: read),
            "nothing named to compare"
        )
    }

    /// git deletes what it extracted as soon as the tool exits, and the
    /// entitlement for it arrives a moment after launch — so an unreadable side
    /// is a real outcome, and it means no comparison rather than a broken one.
    func test_comparison_isNilWhenEitherSideCannotBeRead() {
        XCTAssertNil(
            DiffLaunch.comparison(in: arguments(baseline: baselinePath, current: currentPath)) { _ in nil }
        )
        XCTAssertNil(
            DiffLaunch.comparison(in: arguments(baseline: baselinePath, current: currentPath)) { url in
                url.path == self.baselinePath ? "committed text\n" : nil
            },
            "the side to display is just as necessary"
        )
    }

}
