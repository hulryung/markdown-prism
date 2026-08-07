import Foundation

/// How `git difftool` hands a comparison to the app.
///
/// Three things had to be measured before this shape settled, and each of them
/// rules out something more obvious:
///
/// 1. git cannot run the app binary on the two files it extracted. Executing it
///    directly issues no entitlement for either path, and relocates the working
///    directory into the app's container, so `$REMOTE` — which git names
///    relative to the repository — stops meaning anything. Going through `open`
///    fixes both.
/// 2. `open` grants every file it is given, but a document-based app is handed
///    only one of them: `application(_:openFiles:)` is called once, with one
///    file, whichever it feels like. So the arguments name both paths and the
///    delivered file is ignored entirely.
/// 3. A path named only in `--args` is *not* granted. Both files have to appear
///    as `open` arguments as well, purely to be reachable.
///
///     [difftool "markdown-prism"]
///         cmd = open -W -n -a "Markdown Prism" "$LOCAL" "$REMOTE" \
///               --args --diff --baseline "$LOCAL" --current "$REMOTE" \
///               --directory "$PWD"
///
/// `--directory` is what makes `$REMOTE` usable: the app is told which directory
/// a relative path belongs to, since its own is a sandbox container. Paths that
/// are already absolute — as both sides are when two commits are compared —
/// ignore it.
///
/// `-n` is not optional. Without it an already-running instance is reused, and
/// the arguments it answers with are the ones it was launched with rather than
/// these, so the comparison would never be recognised as one.
enum DiffLaunch {
    /// Both sides, read while they are still on disk: git deletes what it
    /// extracted the moment the tool exits, and the window outlives that.
    struct Comparison: Equatable {
        let baseline: String
        let current: String
        /// What to call the comparison on screen.
        let name: String
    }

    private static let comparisonFlag = "--diff"
    private static let baselineFlag = "--baseline"
    private static let currentFlag = "--current"
    private static let directoryFlag = "--directory"

    /// Whether this process was started to show a comparison.
    static func isRequested(in arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains(comparisonFlag)
    }

    static func declaredBaselinePath(in arguments: [String] = CommandLine.arguments) -> String? {
        value(after: baselineFlag, in: arguments)
    }

    static func declaredCurrentPath(in arguments: [String] = CommandLine.arguments) -> String? {
        value(after: currentFlag, in: arguments)
    }

    /// The comparison the arguments describe, or nil if they do not describe one.
    ///
    /// `read` is a parameter because the entitlement for these files arrives
    /// asynchronously — the same read fails immediately after launch and
    /// succeeds a moment later — so the caller supplies one that waits.
    static func comparison(
        in arguments: [String] = CommandLine.arguments,
        read: (URL) -> String?
    ) -> Comparison? {
        guard isRequested(in: arguments),
              let baselinePath = declaredBaselinePath(in: arguments),
              let currentPath = declaredCurrentPath(in: arguments) else { return nil }

        let directory = value(after: directoryFlag, in: arguments)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let currentURL = URL(fileURLWithPath: currentPath, relativeTo: directory).standardizedFileURL

        guard let baseline = read(URL(fileURLWithPath: baselinePath, relativeTo: directory)),
              let current = read(currentURL) else { return nil }

        return Comparison(baseline: baseline, current: current, name: currentURL.lastPathComponent)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}
