import Foundation

class RecentDocumentsManager: ObservableObject {
    static let shared = RecentDocumentsManager()

    private let key = "recentDocuments"
    private let maxCount = 10

    @Published var recentURLs: [URL] = []

    private init() {
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
        UserDefaults.standard.set(paths, forKey: key)
    }

    private func load() {
        guard let paths = UserDefaults.standard.stringArray(forKey: key) else { return }
        recentURLs = paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: path) ? url : nil
        }
    }
}
