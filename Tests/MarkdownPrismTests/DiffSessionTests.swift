import XCTest
@testable import MarkdownPrism

/// Covers what a pair of revisions means, which is the part of showing changes
/// that has decisions in it: a file git has never seen, a file that is new since
/// the last commit, and a repository the sandbox has not been let into.
@MainActor
final class DiffSessionTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/repo/docs/spec.md")

    /// Stands in for a repository, so no git process or scratch checkout is
    /// needed to drive the states.
    private struct Source: DiffSource {
        var head: String?
        var index: String?
        var summary: String?

        func text(at revision: GitRepository.Revision, for fileURL: URL) throws -> String? {
            revision == .head ? head : index
        }

        func headSummary() -> String? { summary }
    }

    private final class Grant: RepositoryGranting {
        var isGranted: Bool
        var grantsWhenAsked = true
        private(set) var requests = 0

        init(isGranted: Bool) {
            self.isGranted = isGranted
        }

        func activateGrant(containing fileURL: URL) -> Bool { isGranted }

        func requestGrant(containing fileURL: URL) -> Bool {
            requests += 1
            isGranted = grantsWhenAsked
            return isGranted
        }
    }

    /// `grant` is resolved here rather than in the signature: a default argument
    /// is evaluated at the call site, which is not on the main actor.
    private func session(
        _ source: Source = Source(head: "old\n", index: "staged\n"),
        grant: Grant? = nil
    ) -> DiffSession {
        DiffSession(access: grant ?? Grant(isGranted: true), open: { _ in source })
    }

    /// Reading happens off the main thread, so the settled state arrives a hop
    /// later than the call that asked for it.
    private func settled(_ session: DiffSession) async throws -> DiffSession.State {
        for _ in 0..<300 {
            if session.state != .loading { return session.state }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the session never left .loading")
        return session.state
    }

    // MARK: - Comparisons

    func test_lastCommit_comparesTheCommittedVersionAgainstTheEditor() async throws {
        let session = session(Source(head: "one\n", index: "two\n", summary: "abc1234 Add the spec"))
        session.select(.lastCommit, for: file, text: "one\ntyped\n")

        guard case .ready(let comparison) = try await settled(session) else {
            return XCTFail("expected a comparison")
        }
        XCTAssertEqual(comparison.baseline, "one\n")
        XCTAssertNil(comparison.current, "the editor's own text is the other side")
        XCTAssertEqual(comparison.stats, DiffStats(additions: 1, deletions: 0))
        XCTAssertEqual(comparison.headSummary, "abc1234 Add the spec")
    }

    /// Staged changes are two stored versions, so the editor's text — which may
    /// have moved on again — takes no part.
    func test_staged_comparesTheCommittedVersionAgainstTheIndex() async throws {
        let session = session(Source(head: "one\n", index: "one\ntwo\n"))
        session.select(.staged, for: file, text: "something else entirely\n")

        guard case .ready(let comparison) = try await settled(session) else {
            return XCTFail("expected a comparison")
        }
        XCTAssertEqual(comparison.baseline, "one\n")
        XCTAssertEqual(comparison.current, "one\ntwo\n")
        XCTAssertEqual(comparison.stats, DiffStats(additions: 1, deletions: 0))
    }

    func test_unstaged_comparesTheIndexAgainstTheEditor() async throws {
        let session = session(Source(head: "committed\n", index: "staged\n"))
        session.select(.unstaged, for: file, text: "staged\nand typing\n")

        guard case .ready(let comparison) = try await settled(session) else {
            return XCTFail("expected a comparison")
        }
        XCTAssertEqual(comparison.baseline, "staged\n")
        XCTAssertNil(comparison.current)
        XCTAssertEqual(comparison.stats, DiffStats(additions: 1, deletions: 0))
    }

    /// A file added since the last commit has no committed version, but it is
    /// still worth showing — as an all-new document.
    func test_lastCommit_forAFileStagedButNeverCommitted_comparesAgainstNothing() async throws {
        let session = session(Source(head: nil, index: "brand new\n"))
        session.select(.lastCommit, for: file, text: "brand new\n")

        guard case .ready(let comparison) = try await settled(session) else {
            return XCTFail("expected a comparison")
        }
        XCTAssertEqual(comparison.baseline, "")
        XCTAssertEqual(comparison.stats, DiffStats(additions: 1, deletions: 0))
    }

    func test_aFileGitHasNeverSeen_reportsItAsUntracked() async throws {
        let session = session(Source(head: nil, index: nil))
        session.select(.lastCommit, for: file, text: "scratch\n")

        let state = try await settled(session)
        XCTAssertEqual(state, .unavailable(.untracked))
    }

    func test_staged_forAnUntrackedFile_reportsItAsUntracked() async throws {
        let session = session(Source(head: nil, index: nil))
        session.select(.staged, for: file, text: "scratch\n")

        let state = try await settled(session)
        XCTAssertEqual(state, .unavailable(.untracked))
    }

    // MARK: - Sandbox access

    /// Inside the sandbox an ungranted repository looks exactly like no
    /// repository, so an unreachable one offers the panel rather than declaring
    /// the file unversioned.
    func test_anUnreachableRepositoryWithNoGrant_asksForOne() async throws {
        let grant = Grant(isGranted: false)
        let session = DiffSession(
            access: grant,
            open: { _ in throw GitRepository.Failure.notARepository }
        )

        session.select(.lastCommit, for: file, text: "one\n")
        let state = try await settled(session)

        XCTAssertEqual(state, .unavailable(.needsAccess))
        XCTAssertEqual(grant.requests, 0, "the panel is the reader's choice, not automatic")
    }

    /// A build that is not sandboxed, or a repository already within reach,
    /// needs no grant — and must not be asked for one.
    func test_aReadableRepositoryWithNoGrant_neverAsks() async throws {
        let grant = Grant(isGranted: false)
        let session = session(Source(head: "one\n", index: "one\n"), grant: grant)

        session.select(.lastCommit, for: file, text: "one\ntwo\n")

        guard case .ready = try await settled(session) else {
            return XCTFail("expected a comparison")
        }
        XCTAssertEqual(grant.requests, 0)
    }

    func test_grantingAccess_loadsTheComparison() async throws {
        let grant = Grant(isGranted: false)
        let session = DiffSession(access: grant, open: { source in
            // Unreachable until the folder is handed over.
            guard grant.isGranted else { throw GitRepository.Failure.notARepository }
            _ = source
            return Source(head: "one\n", index: "one\n")
        })

        session.select(.lastCommit, for: file, text: "one\n")
        let beforeGrant = try await settled(session)
        XCTAssertEqual(beforeGrant, .unavailable(.needsAccess))

        session.requestAccess(for: file, text: "one\n")
        XCTAssertEqual(grant.requests, 1)
        guard case .ready = try await settled(session) else {
            return XCTFail("granting access should load the comparison")
        }
    }

    func test_decliningTheGrant_leavesTheOfferStanding() async throws {
        let grant = Grant(isGranted: false)
        grant.grantsWhenAsked = false
        let session = DiffSession(
            access: grant,
            open: { _ in throw GitRepository.Failure.notARepository }
        )

        session.select(.lastCommit, for: file, text: "one\n")
        let asked = try await settled(session)
        XCTAssertEqual(asked, .unavailable(.needsAccess))

        session.requestAccess(for: file, text: "one\n")

        XCTAssertEqual(grant.requests, 1)
        XCTAssertEqual(session.state, .unavailable(.needsAccess))
    }

    // MARK: - Failures and switching off

    func test_anUnsavedDocument_hasNoRepositoryToCompareAgainst() {
        let session = session()
        session.select(.lastCommit, for: nil, text: "untitled\n")

        XCTAssertEqual(session.state, .unavailable(.notARepository))
    }

    func test_gitFailures_areReportedAsThemselves() async throws {
        let missing = DiffSession(
            access: Grant(isGranted: true),
            open: { _ in throw GitRepository.Failure.gitUnavailable }
        )
        missing.select(.lastCommit, for: file, text: "one\n")
        let missingState = try await settled(missing)
        XCTAssertEqual(missingState, .unavailable(.gitUnavailable))

        let outside = DiffSession(
            access: Grant(isGranted: true),
            open: { _ in throw GitRepository.Failure.notARepository }
        )
        outside.select(.lastCommit, for: file, text: "one\n")
        let outsideState = try await settled(outside)
        XCTAssertEqual(outsideState, .unavailable(.notARepository))
    }

    func test_switchingOff_clearsTheComparison() async throws {
        let session = session()
        session.select(.lastCommit, for: file, text: "one\n")
        _ = try await settled(session)

        session.select(.off, for: file, text: "one\n")
        XCTAssertEqual(session.state, .off)
    }

    // MARK: - Counting as the reader types

    func test_updateCounts_recountsAgainstTheEditorWithoutRereadingHistory() async throws {
        let session = session(Source(head: "one\n", index: "one\n"))
        session.select(.lastCommit, for: file, text: "one\n")
        _ = try await settled(session)

        session.updateCounts(for: "one\ntwo\nthree\n")

        guard case .ready(let comparison) = session.state else {
            return XCTFail("expected a comparison")
        }
        XCTAssertEqual(comparison.stats, DiffStats(additions: 2, deletions: 0))
        XCTAssertEqual(comparison.baseline, "one\n", "the stored side is untouched")
    }

    /// Typing does not change what is staged, so a staged comparison's counts
    /// must not follow the editor.
    func test_updateCounts_leavesAStagedComparisonAlone() async throws {
        let session = session(Source(head: "one\n", index: "one\ntwo\n"))
        session.select(.staged, for: file, text: "one\n")
        _ = try await settled(session)

        session.updateCounts(for: "wildly different\n")

        guard case .ready(let comparison) = session.state else {
            return XCTFail("expected a comparison")
        }
        XCTAssertEqual(comparison.stats, DiffStats(additions: 1, deletions: 0))
    }
}
