import Foundation

/// Reads a file's committed and staged contents out of a Git repository.
///
/// Nothing here knows about the sandbox or the view layer, which is what keeps
/// it testable against a scratch repository. Earning the right to reach a
/// repository at all is `RepositoryAccess`'s job.
struct GitRepository {
    /// A stored version of a file a diff can be taken against.
    ///
    /// The raw value is the `git` object-name prefix: `HEAD:path` names the last
    /// commit's copy, and a bare `:path` names the staged one.
    enum Revision: String, CaseIterable {
        case head = "HEAD"
        case index = ""
    }

    enum Failure: Error, Equatable {
        /// No usable `git` — Command Line Tools are most likely not installed.
        case gitUnavailable
        /// The file is not inside a repository this process can reach. Under the
        /// sandbox that covers "not granted" as well as "not a repository".
        case notARepository
        case commandFailed(String)
    }

    /// Absolute path of the working tree root.
    let root: URL

    /// The `git` to run, found once.
    ///
    /// Deliberately not `/usr/bin/git`: that is the `xcrun` shim, and `xcrun`
    /// refuses outright inside an App Sandbox — "xcrun: error: cannot be used
    /// within an App Sandbox" — so this app has to find the real binary the shim
    /// would have forwarded to. Those binaries do run under the sandbox, and
    /// stay subject to it, which is the whole point.
    private static let executable: URL? = resolveExecutable()

    /// Which `git` was chosen. Exposed so the tests can guard the choice.
    static var executablePath: String? { executable?.path }

    private static func resolveExecutable() -> URL? {
        var candidates: [String] = []

        // What `xcode-select` points at is the toolchain `xcrun` would have
        // picked, and the symlink recording it is readable from the sandbox
        // even though `xcrun` itself is not.
        if let developerDirectory = try? FileManager.default.destinationOfSymbolicLink(
            atPath: "/var/db/xcode_select_link"
        ) {
            candidates.append(developerDirectory + "/usr/bin/git")
        }

        candidates.append(contentsOf: [
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
            // Last, and only useful unsandboxed — where the shim works fine.
            "/usr/bin/git"
        ])

        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Discovery

    /// Finds the repository `fileURL` belongs to.
    ///
    /// The upward walk is `git`'s own, run from the file's own directory. Inside
    /// the sandbox that walk stops wherever access stops, so a file whose
    /// repository was never granted reads as `notARepository` rather than
    /// reaching outside the grant.
    static func discover(containing fileURL: URL) throws -> GitRepository {
        let result = try run(["rev-parse", "--show-toplevel"], in: fileURL.deletingLastPathComponent())
        guard result.status == 0 else {
            throw failure(for: result, otherwise: .notARepository)
        }

        let path = text(of: result.standardOutput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw Failure.notARepository }
        return GitRepository(root: URL(fileURLWithPath: path, isDirectory: true))
    }

    // MARK: - Reading

    /// The file's contents at `revision`, or nil when the file does not exist
    /// there.
    ///
    /// Absent is not an error: a file added since the last commit simply has no
    /// baseline, and the caller renders that as an all-new document.
    func text(at revision: Revision, for fileURL: URL) throws -> String? {
        let directory = fileURL.deletingLastPathComponent()
        // Naming the file as `./name` relative to its own directory lets git
        // work out the repository-relative path, which is otherwise fiddly to
        // reproduce correctly across symlinked and case-folding paths.
        let object = "\(revision.rawValue):./\(fileURL.lastPathComponent)"

        // `cat-file -e` is the only reliable way to tell "not in this revision"
        // apart from a real failure: reading a missing path out of the index
        // reports the same "ambiguous argument" as a malformed revision does.
        guard try Self.run(["cat-file", "-e", object], in: directory).status == 0 else {
            return nil
        }

        let result = try Self.run(["cat-file", "blob", object], in: directory)
        guard result.status == 0 else {
            throw Self.failure(for: result, otherwise: .commandFailed(Self.errorMessage(result)))
        }
        return try MarkdownDocument.decode(result.standardOutput).text
    }

    /// A short description of the last commit, for labelling what is being
    /// compared against. Nil in a repository without commits.
    func headSummary() -> String? {
        guard let result = try? Self.run(["log", "-1", "--format=%h %s"], in: root),
              result.status == 0 else { return nil }
        let summary = Self.text(of: result.standardOutput).trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    // MARK: - Running git

    private struct Result {
        let status: Int32
        let standardOutput: Data
        let standardError: Data
    }

    private static func run(_ arguments: [String], in directory: URL) throws -> Result {
        guard let executable else { throw Failure.gitUnavailable }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment

        let output = Pipe()
        let errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            // git is known to exist by this point, so a launch failure is the
            // working directory being unreachable rather than a missing tool.
            throw Failure.notARepository
        }

        // Both pipes are drained concurrently, and before waiting on the exit: a
        // blob bigger than the pipe buffer would otherwise wedge git mid-write
        // while we wait for an exit that cannot come.
        var outputData = Data()
        var errorData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.markdownprism.git", attributes: .concurrent)
        queue.async(group: group) { outputData = output.fileHandleForReading.readDataToEndOfFile() }
        queue.async(group: group) { errorData = errors.fileHandleForReading.readDataToEndOfFile() }
        group.wait()
        process.waitUntilExit()

        return Result(
            status: process.terminationStatus,
            standardOutput: outputData,
            standardError: errorData
        )
    }

    /// A deliberately bare environment. The app should read a repository the
    /// same way whatever shell it was launched from, and `LC_ALL` pins the
    /// messages `failure(for:otherwise:)` matches on.
    private static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for inherited in [
            "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE",
            "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR"
        ] {
            environment.removeValue(forKey: inherited)
        }
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["LC_ALL"] = "C"
        environment["PATH"] = "/usr/bin:/bin"
        return environment
    }

    /// With no real toolchain to find, the only candidate left is the shim,
    /// which complains rather than running — either that the developer tools are
    /// missing, or that it will not run under the sandbox. Both mean "no git"
    /// rather than a problem with the repository.
    private static func failure(for result: Result, otherwise fallback: Failure) -> Failure {
        let message = errorMessage(result)
        if message.contains("xcrun") || message.contains("xcode-select")
            || message.contains("no developer tools") {
            return .gitUnavailable
        }
        return fallback
    }

    private static func errorMessage(_ result: Result) -> String {
        text(of: result.standardError).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// git speaks UTF-8, but a blob is whatever the author committed, so this
    /// falls back the same way reading a file from disk does.
    private static func text(of data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
