import AppKit
import Foundation

/// The sandbox grant reading a repository depends on.
///
/// Split out from the store below because a security-scoped bookmark cannot be
/// forged, so this is the seam a test stands in at.
@MainActor
protocol RepositoryGranting {
    /// Opens access to a repository folder granted earlier. False means the
    /// reader has not been asked yet.
    @discardableResult func activateGrant(containing fileURL: URL) -> Bool
    /// Asks the reader for the folder. False means they declined.
    @discardableResult func requestGrant(containing fileURL: URL) -> Bool
}

/// Keeps the sandbox out of the way of reading a Git repository.
///
/// Opening `spec.md` grants this app that one file — not the `.git` directory
/// beside it, and not the folder it sits in — so showing changes needs the
/// reader to hand over the repository folder once. That grant is kept as a
/// security-scoped bookmark and reused for every file in the repository, in
/// this run of the app and in later ones.
@MainActor
final class RepositoryAccess: RepositoryGranting {
    static let shared = RepositoryAccess()

    private let defaults: UserDefaults
    /// Folders whose extension has already been consumed in this process.
    /// Access is never handed back: a granted repository stays readable until
    /// the app quits, which is cheaper and less surprising than reopening the
    /// scope around every read.
    private var opened: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let bookmarks = "repositoryBookmarks"
    }

    // MARK: - Using a grant

    /// Opens access to the repository folder covering `fileURL`, if one was
    /// granted before. False means the reader has not been asked yet.
    @discardableResult
    func activateGrant(containing fileURL: URL) -> Bool {
        guard let (path, bookmark) = grant(containing: fileURL) else { return false }
        if opened.contains(path) { return true }

        var isStale = false
        guard let folder = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            forget(path)
            return false
        }

        guard folder.startAccessingSecurityScopedResource() else {
            forget(path)
            return false
        }
        opened.insert(path)

        // A stale bookmark still resolves, but only once more; refreshing it now
        // — while access is open — is what keeps the grant alive across moves
        // and OS updates.
        if isStale || folder.standardizedFileURL.path != path {
            forget(path)
            remember(folder)
            opened.insert(folder.standardizedFileURL.path)
        }
        return true
    }

    /// Whether a repository folder covering `fileURL` has already been granted.
    func hasGrant(containing fileURL: URL) -> Bool {
        grant(containing: fileURL) != nil
    }

    // MARK: - Asking for a grant

    /// Asks the reader for the repository folder holding `fileURL`.
    ///
    /// The panel is the only way a sandboxed app can widen its own reach, so
    /// this is a deliberate, explained prompt rather than something to retry
    /// quietly in the background.
    @discardableResult
    func requestGrant(containing fileURL: URL) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Grant Access"

        // Opening at the repository rather than at the file's own folder, which
        // for anything under a subdirectory means climbing back out before the
        // panel is even useful. The root is only a guess — the reader can still
        // go anywhere from here — but it is right nearly every time.
        let root = GitRepository.likelyRoot(containing: fileURL)
        panel.directoryURL = root ?? fileURL.deletingLastPathComponent()
        panel.message = root.map { root in
            """
            Grant access to \u{201C}\(root.lastPathComponent)\u{201D} so Markdown Prism can read its \
            history and show changes to \u{201C}\(fileURL.lastPathComponent)\u{201D}. It asks once per repository.
            """
        } ?? """
            Choose the Git repository folder that contains \u{201C}\(fileURL.lastPathComponent)\u{201D}.
            Markdown Prism reads its history to show changes, and remembers the folder so it only asks once.
            """

        guard panel.runModal() == .OK, let folder = panel.url else { return false }

        guard folder.contains(fileURL) else {
            let alert = NSAlert()
            alert.messageText = "That folder does not contain \u{201C}\(fileURL.lastPathComponent)\u{201D}"
            alert.informativeText = "Choose the repository folder the file lives in, or one of its parents."
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }

        remember(folder)
        // The panel itself is what granted access for this run, so there is no
        // scope to open on top of it — the bookmark is only for next launch.
        opened.insert(folder.standardizedFileURL.path)
        return true
    }

    // MARK: - Stored bookmarks

    private func grant(containing fileURL: URL) -> (path: String, bookmark: Data)? {
        // Longest match first, so a repository nested inside another granted
        // folder is preferred over its parent.
        bookmarks()
            .filter { path, _ in URL(fileURLWithPath: path, isDirectory: true).contains(fileURL) }
            .max { $0.key.count < $1.key.count }
            .map { ($0.key, $0.value) }
    }

    private func bookmarks() -> [String: Data] {
        defaults.dictionary(forKey: Key.bookmarks) as? [String: Data] ?? [:]
    }

    private func remember(_ folder: URL) {
        guard let bookmark = try? folder.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var stored = bookmarks()
        stored[folder.standardizedFileURL.path] = bookmark
        defaults.set(stored, forKey: Key.bookmarks)
    }

    private func forget(_ path: String) {
        var stored = bookmarks()
        stored.removeValue(forKey: path)
        defaults.set(stored, forKey: Key.bookmarks)
        opened.remove(path)
    }
}

private extension URL {
    /// Whether `other` sits inside this folder, comparing the paths the file
    /// system actually resolves to so a symlinked temporary directory does not
    /// read as being somewhere else.
    func contains(_ other: URL) -> Bool {
        let folder = resolvingSymlinksInPath().standardizedFileURL.path
        let target = other.resolvingSymlinksInPath().standardizedFileURL.path
        guard folder != "/" else { return true }
        return target.hasPrefix(folder + "/")
    }
}
