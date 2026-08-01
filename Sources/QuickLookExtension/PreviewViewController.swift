import Cocoa
import WebKit
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var completionHandler: ((Error?) -> Void)?
    private var markdown = ""

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let data = try Data(contentsOf: url)
            markdown = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? ""
        } catch {
            handler(error)
            return
        }

        // The Quick Look shell carries a strict Content-Security-Policy; the
        // in-app preview.html is the same page without it.
        guard let templateURL = Bundle.main.url(
            forResource: "preview-quicklook",
            withExtension: "html",
            subdirectory: "Resources"
        ) else {
            handler(CocoaError(.fileNoSuchFile))
            return
        }

        completionHandler = handler
        // Loaded straight out of the bundle. Staging a copy of css/ and vendor/
        // in a temp directory cost 3.5MB of file writes on every preview.
        webView.loadFileURL(
            templateURL,
            allowingReadAccessTo: templateURL.deletingLastPathComponent()
        )
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let handler = completionHandler else { return }
        completionHandler = nil

        guard let encoded = try? JSONEncoder().encode(markdown),
              let jsonString = String(data: encoded, encoding: .utf8) else {
            handler(CocoaError(.coderInvalidValue))
            return
        }

        // The template defines renderMarkdown on DOMContentLoaded, which has
        // fired by the time the load finishes.
        webView.evaluateJavaScript("window.renderMarkdown(\(jsonString));") { _, error in
            handler(error)
        }
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
