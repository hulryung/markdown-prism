import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let markdown: String
    var fileURL: URL?
    var onOpenFile: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let handler = WeakScriptMessageHandler(delegate: context.coordinator)
        config.userContentController.add(handler, name: "linkClicked")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.fileURL = fileURL
        context.coordinator.onOpenFile = onOpenFile

        let templateURL: URL? = {
            #if SWIFT_PACKAGE
            return Bundle.module.url(
                forResource: "preview",
                withExtension: "html",
                subdirectory: "Resources"
            )
            #else
            return Bundle.main.resourceURL?
                .appendingPathComponent("Resources")
                .appendingPathComponent("preview.html")
            #endif
        }()

        if let templateURL, FileManager.default.fileExists(atPath: templateURL.path) {
            webView.loadFileURL(templateURL, allowingReadAccessTo: templateURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<html><body><pre>Failed to load preview template.</pre></body></html>", baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.currentMarkdown = markdown
        context.coordinator.fileURL = fileURL
        context.coordinator.onOpenFile = onOpenFile
        if context.coordinator.isLoaded {
            context.coordinator.renderCurrentMarkdown()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var isLoaded = false
        var currentMarkdown = ""
        var fileURL: URL?
        var onOpenFile: ((URL) -> Void)?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            renderCurrentMarkdown()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "linkClicked",
                  let href = message.body as? String else {
                return
            }
            handleLinkClick(href: href)
        }

        func renderCurrentMarkdown() {
            guard let webView, isLoaded else {
                return
            }

            guard let encoded = try? JSONEncoder().encode(currentMarkdown),
                  let jsonString = String(data: encoded, encoding: .utf8)
            else {
                return
            }

            let script = "window.renderMarkdown(\(jsonString));"
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    print("render error: \(error.localizedDescription)")
                }
            }
        }

        private func handleLinkClick(href: String) {
            // External URLs - open in default browser
            if href.hasPrefix("http://") || href.hasPrefix("https://") {
                if let url = URL(string: href) {
                    NSWorkspace.shared.open(url)
                }
                return
            }

            // Mailto links
            if href.hasPrefix("mailto:") {
                if let url = URL(string: href) {
                    NSWorkspace.shared.open(url)
                }
                return
            }

            // Relative .md / .markdown links - resolve against current file
            let ext = (href as NSString).pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                guard let fileURL else { return }
                let baseDir = fileURL.deletingLastPathComponent()
                let resolved = URL(fileURLWithPath: href, relativeTo: baseDir).standardized
                if FileManager.default.fileExists(atPath: resolved.path) {
                    DispatchQueue.main.async {
                        self.onOpenFile?(resolved)
                    }
                }
                return
            }

            // Other URLs - try to open externally
            if let url = URL(string: href) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// Weak wrapper to avoid retain cycle between WKUserContentController and Coordinator.
private class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
