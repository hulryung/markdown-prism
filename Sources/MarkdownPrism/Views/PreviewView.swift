import SwiftUI
import WebKit

struct PreviewView: NSViewRepresentable {
    let markdown: String
    let zoomScale: Double
    let searchText: String
    let searchRevision: Int
    let isRegex: Bool
    let useFullWidth: Bool
    let fontStack: String
    let fontSize: CGFloat
    let scrollSync: ScrollSyncBus
    var fileURL: URL?
    var onOpenFile: ((URL) -> Void)?
    var onSearchResults: ((Int, Int) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let handler = WeakScriptMessageHandler(delegate: context.coordinator)
        config.userContentController.add(handler, name: "linkClicked")
        config.userContentController.add(handler, name: "previewScrolled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.pageZoom = zoomScale
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.currentZoomScale = zoomScale
        context.coordinator.pendingSearchText = searchText
        context.coordinator.pendingSearchRevision = searchRevision
        context.coordinator.pendingIsRegex = isRegex
        context.coordinator.pendingFullWidth = useFullWidth
        context.coordinator.pendingTypography = Typography(stack: fontStack, size: fontSize)
        context.coordinator.fileURL = fileURL
        context.coordinator.onOpenFile = onOpenFile
        context.coordinator.onSearchResults = onSearchResults
        context.coordinator.bind(to: scrollSync)

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
        let c = context.coordinator
        c.currentMarkdown = markdown
        c.currentZoomScale = zoomScale
        c.pendingSearchText = searchText
        c.pendingSearchRevision = searchRevision
        c.pendingIsRegex = isRegex
        c.pendingFullWidth = useFullWidth
        c.pendingTypography = Typography(stack: fontStack, size: fontSize)
        c.fileURL = fileURL
        c.onOpenFile = onOpenFile
        c.onSearchResults = onSearchResults
        c.bind(to: scrollSync)
        if c.isLoaded {
            c.sync()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var isLoaded = false
        var currentMarkdown = ""
        var renderedMarkdown = ""
        var currentZoomScale = ZoomState.defaultScale
        var pendingSearchText = ""
        var pendingSearchRevision = 0
        var pendingIsRegex = false
        var pendingFullWidth = false
        var pendingTypography = Typography(stack: "", size: 16)
        private var appliedTypography: Typography?
        private var appliedFullWidth: Bool?
        private var appliedSearchText: String?
        private var appliedSearchRevision = 0
        private var appliedIsRegex = false
        var fileURL: URL?
        var onOpenFile: ((URL) -> Void)?
        var onSearchResults: ((Int, Int) -> Void)?
        private weak var scrollSync: ScrollSyncBus?

        func bind(to scrollSync: ScrollSyncBus) {
            self.scrollSync = scrollSync
            scrollSync.scrollPreview = { [weak self] line in
                self?.scrollToSourceLine(line)
            }
        }

        private func scrollToSourceLine(_ line: Int) {
            guard isLoaded, let webView else { return }
            webView.evaluateJavaScript("window.scrollToSourceLine(\(line));") { _, _ in }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            renderedMarkdown = ""
            appliedSearchText = nil
            appliedTypography = nil
            sync()
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
            switch message.name {
            case "linkClicked":
                guard let href = message.body as? String else { return }
                handleLinkClick(href: href)
            case "previewScrolled":
                guard let line = message.body as? NSNumber else { return }
                scrollSync?.previewDidScroll(toLine: line.intValue)
            default:
                break
            }
        }

        func sync() {
            guard isLoaded else { return }
            applyZoomIfNeeded()
            applyFullWidthIfNeeded()
            applyTypographyIfNeeded()
            let didRender = renderIfNeeded()
            if didRender { appliedSearchText = nil }
            searchIfNeeded()
        }

        private func applyFullWidthIfNeeded() {
            guard let webView else { return }
            guard pendingFullWidth != appliedFullWidth else { return }
            appliedFullWidth = pendingFullWidth
            webView.evaluateJavaScript("window.setFullWidth(\(pendingFullWidth));") { _, _ in }
        }

        private func applyTypographyIfNeeded() {
            guard let webView else { return }
            guard pendingTypography != appliedTypography else { return }
            appliedTypography = pendingTypography

            guard let encoded = try? JSONEncoder().encode(pendingTypography.stack),
                  let stack = String(data: encoded, encoding: .utf8) else { return }
            webView.evaluateJavaScript(
                "window.setTypography(\(stack), \(pendingTypography.size));"
            ) { _, _ in }
        }

        private func applyZoomIfNeeded() {
            guard let webView else { return }
            if webView.pageZoom != currentZoomScale {
                webView.pageZoom = currentZoomScale
            }
        }

        private func renderIfNeeded() -> Bool {
            guard let webView else { return false }
            guard renderedMarkdown != currentMarkdown else { return false }

            guard let encoded = try? JSONEncoder().encode(currentMarkdown),
                  let jsonString = String(data: encoded, encoding: .utf8) else { return false }

            webView.evaluateJavaScript("window.renderMarkdown(\(jsonString));") { _, error in
                if let error { print("render error: \(error.localizedDescription)") }
            }
            renderedMarkdown = currentMarkdown
            return true
        }

        private func searchIfNeeded() {
            guard let webView else { return }

            if pendingSearchText != appliedSearchText || pendingIsRegex != appliedIsRegex {
                appliedSearchText = pendingSearchText
                appliedSearchRevision = pendingSearchRevision
                appliedIsRegex = pendingIsRegex

                if pendingSearchText.isEmpty {
                    webView.evaluateJavaScript("window.clearFindHighlights();") { _, _ in }
                    DispatchQueue.main.async { self.onSearchResults?(0, 0) }
                } else {
                    guard let encoded = try? JSONEncoder().encode(pendingSearchText),
                          let jsonString = String(data: encoded, encoding: .utf8) else { return }
                    let regexFlag = pendingIsRegex ? "true" : "false"
                    webView.evaluateJavaScript("window.findInPreview(\(jsonString), \(regexFlag));") { [weak self] result, _ in
                        self?.handleSearchResult(result)
                    }
                }
            } else if pendingSearchRevision != appliedSearchRevision {
                let fn = pendingSearchRevision > appliedSearchRevision ? "findNextMatch" : "findPreviousMatch"
                appliedSearchRevision = pendingSearchRevision
                webView.evaluateJavaScript("window.\(fn)();") { [weak self] result, _ in
                    self?.handleSearchResult(result)
                }
            }
        }

        private func handleSearchResult(_ result: Any?) {
            guard let dict = result as? [String: Any],
                  let count = dict["count"] as? Int,
                  let current = dict["current"] as? Int else { return }
            DispatchQueue.main.async { self.onSearchResults?(count, current) }
        }

        private func handleLinkClick(href: String) {
            if href.hasPrefix("http://") || href.hasPrefix("https://") {
                if let url = URL(string: href) {
                    NSWorkspace.shared.open(url)
                }
                return
            }

            if href.hasPrefix("mailto:") {
                if let url = URL(string: href) {
                    NSWorkspace.shared.open(url)
                }
                return
            }

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

            print("Ignored link click with unsupported scheme: \(href)")
        }
    }
}

/// The preview's body face and base size, as chosen in Settings.
struct Typography: Equatable {
    var stack: String
    var size: CGFloat
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
