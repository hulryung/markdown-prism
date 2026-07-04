import Foundation

class RecentDocumentsManager: ObservableObject {
    static let shared = RecentDocumentsManager()

    private let key = "recentDocuments"
    private let maxCount = 10
    private let defaults: UserDefaults

    @Published var recentURLs: [URL] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addURL(_ url: URL) {
        var urls = recentURLs
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        if urls.count > maxCount {
            urls = Array(urls.prefix(maxCount))
        }
        recentURLs = urls
        save()
    }

    func clear() {
        recentURLs = []
        save()
    }

    private func save() {
        let paths = recentURLs.map { $0.path }
        defaults.set(paths, forKey: key)
    }

    private func load() {
        guard let paths = defaults.stringArray(forKey: key) else { return }
        recentURLs = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
    }
}
