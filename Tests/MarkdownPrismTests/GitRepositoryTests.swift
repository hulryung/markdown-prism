import XCTest
@testable import MarkdownPrism

/// Exercises the git layer against a scratch repository.
///
/// `GitRepository` deliberately knows nothing about the sandbox or the views, so
/// everything it does can be checked here rather than by opening a window.
final class GitRepositoryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("markdown-prism-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try git("init", "-q", "-b", "main", ".")
        try git("config", "user.email", "tests@example.com")
        try git("config", "user.name", "Markdown Prism Tests")
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        try super.tearDownWithError()
    }

    // MARK: - Reading revisions

    func test_textAtHead_returnsTheCommittedContents() throws {
        let file = try write("spec.md", "# Spec\n\nCommitted.\n")
        try git("add", "spec.md")
        try git("commit", "-qm", "add spec")
        try write("spec.md", "# Spec\n\nEdited on disk.\n")

        let repository = try GitRepository.discover(containing: file)
        XCTAssertEqual(try repository.text(at: .head, for: file), "# Spec\n\nCommitted.\n")
    }

    func test_textAtIndex_returnsTheStagedContents() throws {
        let file = try write("spec.md", "one\n")
        try git("add", "spec.md")
        try git("commit", "-qm", "add spec")

        try write("spec.md", "two\n")
        try git("add", "spec.md")
        try write("spec.md", "three\n")

        let repository = try GitRepository.discover(containing: file)
        XCTAssertEqual(try repository.text(at: .head, for: file), "one\n")
        XCTAssertEqual(try repository.text(at: .index, for: file), "two\n")
    }

    /// A file added since the last commit has no baseline, which the preview
    /// renders as an all-new document rather than reporting as an error.
    func test_textAtHead_forAFileStagedButNeverCommitted_returnsNil() throws {
        let existing = try write("readme.md", "readme\n")
        try git("add", "readme.md")
        try git("commit", "-qm", "init")

        let file = try write("spec.md", "brand new\n")
        try git("add", "spec.md")

        let repository = try GitRepository.discover(containing: existing)
        XCTAssertNil(try repository.text(at: .head, for: file))
        XCTAssertEqual(try repository.text(at: .index, for: file), "brand new\n")
    }

    func test_textAtAnyRevision_forAnUntrackedFile_returnsNil() throws {
        let existing = try write("readme.md", "readme\n")
        try git("add", "readme.md")
        try git("commit", "-qm", "init")

        let file = try write("scratch.md", "never added\n")

        let repository = try GitRepository.discover(containing: existing)
        XCTAssertNil(try repository.text(at: .head, for: file))
        XCTAssertNil(try repository.text(at: .index, for: file))
    }

    func test_textAtHead_readsAFileInASubdirectory() throws {
        let file = try write("docs/guide.md", "# Guide\n")
        try git("add", "docs/guide.md")
        try git("commit", "-qm", "add guide")
        try write("docs/guide.md", "# Guide\n\nMore.\n")

        let repository = try GitRepository.discover(containing: file)
        XCTAssertEqual(try repository.text(at: .head, for: file), "# Guide\n")
    }

    // MARK: - Discovery

    func test_discover_fromASubdirectory_findsTheRepositoryRoot() throws {
        let file = try write("docs/deep/guide.md", "# Guide\n")

        let repository = try GitRepository.discover(containing: file)
        XCTAssertEqual(
            repository.root.resolvingSymlinksInPath().standardizedFileURL.path,
            root.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func test_discover_outsideARepository_throwsNotARepository() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("markdown-prism-plain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let file = outside.appendingPathComponent("loose.md")
        try "# Loose\n".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try GitRepository.discover(containing: file)) { error in
            XCTAssertEqual(error as? GitRepository.Failure, .notARepository)
        }
    }

    func test_headSummary_describesTheLastCommit() throws {
        let file = try write("spec.md", "one\n")
        try git("add", "spec.md")
        try git("commit", "-qm", "Spec: describe the thing")

        let repository = try GitRepository.discover(containing: file)
        let summary = try XCTUnwrap(repository.headSummary())
        XCTAssertTrue(summary.hasSuffix("Spec: describe the thing"), summary)
    }

    func test_headSummary_inARepositoryWithoutCommits_isNil() throws {
        let file = try write("spec.md", "one\n")

        let repository = try GitRepository.discover(containing: file)
        XCTAssertNil(repository.headSummary())
    }

    // MARK: - Counts

    /// The bar above the preview reports additions and deletions, and a number
    /// that disagrees with `git diff --stat` is worse than no number at all.
    /// Checked against git itself rather than a hand-computed expectation.
    func test_diffStats_agreeWithGit() throws {
        let file = try write("spec.md", """
        # Spec

        ## Goal

        Capture what the user did.

        ## Capture

        - Record at 30 fps
        - Store one blob
        - Drop over 50 MB

        ## Retention

        Kept for 30 days.

        """)
        try git("add", "spec.md")
        try git("commit", "-qm", "Spec: describe it")

        // Staged: a changed line, an added line, and a line split into two.
        try write("spec.md", """
        # Spec

        ## Goal

        Capture what the user did.

        ## Capture

        - Record at 60 fps
        - Store one blob
        - Drop over 50 MB
        - Emit a heartbeat

        ## Retention

        Kept for 30 days, then
        deleted nightly.

        """)
        try git("add", "spec.md")

        // Unstaged on top: a whole new section and another changed line.
        try write("spec.md", """
        # Spec

        ## Goal

        Capture what the user did.

        ## Capture

        - Record at 60 fps
        - Store one blob
        - Drop over 50 MB
        - Emit a heartbeat

        ## Consent

        Off until accepted.

        ## Retention

        Kept for 7 days, then
        deleted nightly.

        """)

        let repository = try GitRepository.discover(containing: file)
        let head = try XCTUnwrap(try repository.text(at: .head, for: file))
        let index = try XCTUnwrap(try repository.text(at: .index, for: file))
        let working = try String(contentsOf: file, encoding: .utf8)

        XCTAssertEqual(
            DiffStats.between(head, working),
            try numstat(["diff", "--numstat", "HEAD", "--", "spec.md"]),
            "since the last commit"
        )
        XCTAssertEqual(
            DiffStats.between(head, index),
            try numstat(["diff", "--numstat", "--cached", "HEAD", "--", "spec.md"]),
            "staged"
        )
        XCTAssertEqual(
            DiffStats.between(index, working),
            try numstat(["diff", "--numstat", "--", "spec.md"]),
            "unstaged"
        )
    }

    // MARK: - Finding the repository to ask for

    /// What the open panel starts at. Reported by looking rather than by running
    /// git, because it has to work before the app has been granted anything.
    func test_likelyRoot_findsTheRepositoryFromASubdirectory() throws {
        let file = try write("docs/deep/guide.md", "# Guide\n")

        let found = try XCTUnwrap(GitRepository.likelyRoot(containing: file))
        XCTAssertEqual(
            found.resolvingSymlinksInPath().standardizedFileURL.path,
            root.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func test_likelyRoot_findsTheRepositoryFromTheRootItself() throws {
        let file = try write("spec.md", "# Spec\n")

        let found = try XCTUnwrap(GitRepository.likelyRoot(containing: file))
        XCTAssertEqual(
            found.resolvingSymlinksInPath().standardizedFileURL.path,
            root.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    /// `.git` is a file rather than a directory in a worktree and in a
    /// submodule, so its kind must not be part of the test.
    func test_likelyRoot_acceptsAGitFileAsWellAsAGitDirectory() throws {
        let elsewhere = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("markdown-prism-worktree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: elsewhere.appendingPathComponent("docs"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: elsewhere) }

        try "gitdir: /somewhere/.git/worktrees/x\n"
            .write(to: elsewhere.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let file = elsewhere.appendingPathComponent("docs/spec.md")
        try "# Spec\n".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            GitRepository.likelyRoot(containing: file)?.standardizedFileURL.path,
            elsewhere.standardizedFileURL.path
        )
    }

    func test_likelyRoot_outsideARepository_isNil() throws {
        let outside = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("markdown-prism-loose-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let file = outside.appendingPathComponent("loose.md")
        try "# Loose\n".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertNil(GitRepository.likelyRoot(containing: file))
    }

    /// A repository inside another one belongs to the nearer of the two.
    func test_likelyRoot_prefersTheNearestRepository() throws {
        let inner = root.appendingPathComponent("vendor/library", isDirectory: true)
        try FileManager.default.createDirectory(
            at: inner.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        let file = try write("vendor/library/README.md", "# Library\n")

        XCTAssertEqual(
            GitRepository.likelyRoot(containing: file)?.resolvingSymlinksInPath().standardizedFileURL.path,
            inner.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    // MARK: - Which git gets run

    /// `/usr/bin/git` is the `xcrun` shim, and `xcrun` refuses to run inside an
    /// App Sandbox at all. Choosing it would pass every test here — which runs
    /// unsandboxed — and then fail in the shipped app, so the choice is checked
    /// rather than assumed.
    func test_theResolvedGit_isNotTheXcrunShim() throws {
        let toolchains = [
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
        ]
        let selected = (try? FileManager.default.destinationOfSymbolicLink(
            atPath: "/var/db/xcode_select_link"
        )).map { [$0 + "/usr/bin/git"] } ?? []

        guard (toolchains + selected).contains(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("no real toolchain on this machine, so the shim is all there is")
        }
        XCTAssertNotEqual(GitRepository.executablePath, "/usr/bin/git")
    }

    func test_theResolvedGit_runs() throws {
        let path = try XCTUnwrap(GitRepository.executablePath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let version = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(version.hasPrefix("git version"), version)
    }

    // MARK: - Helpers

    @discardableResult
    private func write(_ path: String, _ contents: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// What `git diff --numstat` reports, as a `DiffStats` to compare against.
    private func numstat(_ arguments: [String]) throws -> DiffStats {
        let fields = try gitOutput(arguments)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t")
        guard fields.count >= 2,
              let additions = Int(fields[0]),
              let deletions = Int(fields[1]) else { return .none }
        return DiffStats(additions: additions, deletions: deletions)
    }

    private func git(_ arguments: String...) throws {
        _ = try gitOutput(arguments)
    }

    /// Runs git isolated from whatever configuration the machine running the
    /// tests happens to have, so a developer's `~/.gitconfig` cannot change the
    /// result.
    @discardableResult
    private func gitOutput(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": root.path,
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "LC_ALL": "C"
        ]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        let result = output.fileHandleForReading.readDataToEndOfFile()
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw XCTSkip(
                "git \(arguments.joined(separator: " ")) failed: "
                    + String(decoding: message, as: UTF8.self)
            )
        }
        return String(decoding: result, as: UTF8.self)
    }
}
