import Foundation

class RecentDocumentsManager: ObservableObject {
    static let shared = RecentDocumentsManager()

    /// A recent document plus the security-scoped bookmark that lets a
    /// sandboxed relaunch reopen it. `bookmark` is nil for entries migrated
    /// from the pre-bookmark format or when bookmark creation failed.
    struct Entry: Equatable {
        let url: URL
        let bookmark: Data?
    }

    private let entriesKey = "recentDocumentEntries"
    private let legacyPathsKey = "recentDocuments"
    private let maxCount = 10
    private let defaults: UserDefaults

    @Published private(set) var entries: [Entry] = []

    var recentURLs: [URL] {
        entries.map(\.url)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addURL(_ url: URL) {
        let entry = Entry(url: url, bookmark: Self.makeBookmark(for: url))
        var next = entries.filter { !Self.isSameFile($0.url, url) }
        next.insert(entry, at: 0)
        if next.count > maxCount {
            next = Array(next.prefix(maxCount))
        }
        entries = next
        save()
    }

    func remove(_ url: URL) {
        let next = entries.filter { !Self.isSameFile($0.url, url) }
        guard next.count != entries.count else { return }
        entries = next
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// Starts security-scoped access for a recent document.
    ///
    /// The returned token must be held for as long as the file stays open.
    /// A nil result means no scoped access applies — either the entry has no
    /// bookmark, or the caller already holds access from this session.
    func beginAccess(to url: URL) -> SecurityScopedAccess? {
        guard let entry = entries.first(where: { Self.isSameFile($0.url, url) }),
              entry.bookmark != nil else {
            return nil
        }
        return SecurityScopedAccess(url: entry.url)
    }

    /// Resolving a bookmark returns the symlink-resolved path (`/private/var/…`
    /// where the Open panel handed back `/var/…`), so entries are matched on the
    /// resolved form to avoid duplicates for one file.
    private static func isSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs == rhs || lhs.resolvingSymlinksInPath() == rhs.resolvingSymlinksInPath()
    }

    private static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func save() {
        let items: [[String: Any]] = entries.map { entry in
            var item: [String: Any] = ["path": entry.url.path]
            if let bookmark = entry.bookmark {
                item["bookmark"] = bookmark
            }
            return item
        }
        defaults.set(items, forKey: entriesKey)
        defaults.removeObject(forKey: legacyPathsKey)
    }

    private func load() {
        if let items = defaults.array(forKey: entriesKey) as? [[String: Any]] {
            entries = items.compactMap(Self.entry(from:))
            return
        }

        // Migrate the pre-bookmark format. These paths carry no sandbox
        // extension, so they stay readable only until the user reopens them
        // through the Open panel, which re-adds them with a bookmark.
        guard let paths = defaults.stringArray(forKey: legacyPathsKey) else { return }
        entries = paths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return Entry(url: URL(fileURLWithPath: path), bookmark: nil)
        }
    }

    private static func entry(from item: [String: Any]) -> Entry? {
        if let bookmark = item["bookmark"] as? Data {
            var isStale = false
            // Resolving yields a URL carrying the sandbox extension; that is
            // the URL `beginAccess(to:)` later starts access on.
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return Entry(url: url, bookmark: bookmark)
            }
        }

        guard let path = item["path"] as? String,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return Entry(url: URL(fileURLWithPath: path), bookmark: nil)
    }
}
