import Cocoa
import WebKit
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var completionHandler: ((Error?) -> Void)?
    private var tempDir: URL?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let markdown: String
        do {
            let data = try Data(contentsOf: url)
            markdown = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? ""
        } catch {
            handler(error)
            return
        }

        guard let resourcesURL = Bundle.main.url(
            forResource: "preview",
            withExtension: "html",
            subdirectory: "Resources"
        )?.deletingLastPathComponent() else {
            handler(CocoaError(.fileReadCorruptFile))
            return
        }

        do {
            let (htmlURL, dir) = try buildPreviewHTML(
                markdown: markdown,
                resourcesURL: resourcesURL
            )
            self.tempDir = dir
            self.completionHandler = handler
            webView.loadFileURL(htmlURL, allowingReadAccessTo: dir)
        } catch {
            handler(error)
        }
    }

    private func buildPreviewHTML(markdown: String, resourcesURL: URL) throws -> (htmlURL: URL, tempDir: URL) {
        let templateURL = resourcesURL.appendingPathComponent("preview.html")
        let templateHTML = try String(contentsOf: templateURL, encoding: .utf8)

        let encoded = try JSONEncoder().encode(markdown)
        guard let jsonString = String(data: encoded, encoding: .utf8) else {
            throw CocoaError(.coderInvalidValue)
        }

        // Embed markdown content directly — replace the empty initial render call
        let modifiedHTML = templateHTML.replacingOccurrences(
            of: "renderMarkdown('');",
            with: "renderMarkdown(\(jsonString));"
        )

        // Create temp directory with symlinks to bundle resources
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fm = FileManager.default
        for subdir in ["css", "vendor"] {
            let source = resourcesURL.appendingPathComponent(subdir)
            let dest = dir.appendingPathComponent(subdir)
            try fm.createSymbolicLink(at: dest, withDestinationURL: source)
        }

        let htmlURL = dir.appendingPathComponent("preview.html")
        try modifiedHTML.write(to: htmlURL, atomically: true, encoding: .utf8)

        return (htmlURL, dir)
    }

    private func cleanup() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
            tempDir = nil
        }
    }

    deinit {
        cleanup()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completionHandler?(nil)
        completionHandler = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completionHandler?(error)
        completionHandler = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        completionHandler?(error)
        completionHandler = nil
    }
}
