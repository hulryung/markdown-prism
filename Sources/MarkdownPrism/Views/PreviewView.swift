import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

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
        if context.coordinator.isLoaded {
            context.coordinator.renderCurrentMarkdown()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var isLoaded = false
        var currentMarkdown = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            renderCurrentMarkdown()
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
    }
}
