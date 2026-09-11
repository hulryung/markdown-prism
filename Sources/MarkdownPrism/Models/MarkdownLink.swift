import Foundation

/// Interprets links as URLs, so escaped filenames and fragments do not become
/// literal parts of a local path.
enum MarkdownLink {
    enum Destination: Equatable {
        case external(URL)
        case document(URL)
    }

    static func destination(for href: String, relativeTo fileURL: URL?) -> Destination? {
        guard !href.isEmpty, !href.hasPrefix("#"), !href.hasPrefix("//"),
              let link = URL(string: href) else { return nil }

        if let scheme = link.scheme?.lowercased() {
            if ["http", "https", "mailto"].contains(scheme) { return .external(link) }
            guard scheme == "file" else { return nil }
        } else if fileURL == nil {
            return nil
        }

        let base = fileURL?.deletingLastPathComponent()
        guard let resolved = URL(string: href, relativeTo: base)?.absoluteURL,
              resolved.isFileURL,
              resolved.host == nil || resolved.host == "" || resolved.host == "localhost",
              ["md", "markdown"].contains(resolved.pathExtension.lowercased()),
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true) else { return nil }

        // Open the document even when the link names a heading inside it.
        // In-document anchors are already handled by the preview itself.
        components.fragment = nil
        components.query = nil
        guard let url = components.url else { return nil }
        return .document(url.standardizedFileURL)
    }
}
