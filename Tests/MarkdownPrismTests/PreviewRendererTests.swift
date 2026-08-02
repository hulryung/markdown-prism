import WebKit
import XCTest

/// Drives the real preview shells in a headless WKWebView.
///
/// The renderer is 300+ lines of JavaScript that nothing else exercises, and
/// the Quick Look shell carries the Content-Security-Policy that keeps a
/// previewed file from reaching the network — both are only as good as what is
/// checked here.
final class PreviewRendererTests: XCTestCase {
    private enum Shell: String {
        case app = "preview.html"
        case quickLook = "preview-quicklook.html"
    }

    /// Resources are read from the source tree rather than a bundle: the test
    /// target has no copy of them, and the app target's bundle is not built for
    /// `swift test` on every platform.
    private static var resourcesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // MarkdownPrismTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Sources/MarkdownPrism/Resources")
    }

    private final class Loader: NSObject, WKNavigationDelegate {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        private var onLoad: (() -> Void)?

        func load(_ url: URL, then onLoad: @escaping () -> Void) {
            self.onLoad = onLoad
            webView.navigationDelegate = self
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoad?()
            onLoad = nil
        }
    }

    private var loader: Loader!

    override func setUp() {
        super.setUp()
        loader = Loader()
    }

    override func tearDown() {
        loader = nil
        super.tearDown()
    }

    /// Renders `markdown` in `shell`, then evaluates `script` and returns its value.
    private func render(
        _ markdown: String,
        in shell: Shell = .app,
        settleFor settle: TimeInterval = 1.5,
        then script: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Any? {
        let templateURL = Self.resourcesURL.appendingPathComponent(shell.rawValue)
        let loaded = expectation(description: "page loaded")
        loader.load(templateURL) { loaded.fulfill() }
        wait(for: [loaded], timeout: 30)

        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(markdown), encoding: .utf8))
        let rendered = expectation(description: "markdown rendered")
        var renderError: Error?
        loader.webView.evaluateJavaScript("window.renderMarkdown(\(encoded)); 1") { _, error in
            renderError = error
            rendered.fulfill()
        }
        wait(for: [rendered], timeout: 30)
        if let renderError {
            XCTFail("render failed: \(renderError.localizedDescription)", file: file, line: line)
            return nil
        }

        // KaTeX and Mermaid finish asynchronously after renderMarkdown returns.
        let settled = expectation(description: "async renderers settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { settled.fulfill() }
        wait(for: [settled], timeout: settle + 10)

        var result: Any?
        var probeError: Error?
        let probed = expectation(description: "probe evaluated")
        loader.webView.evaluateJavaScript(script) { value, error in
            result = value
            probeError = error
            probed.fulfill()
        }
        wait(for: [probed], timeout: 30)
        if let probeError {
            XCTFail("probe failed: \(probeError.localizedDescription)", file: file, line: line)
        }
        return result
    }

    private func renderBool(
        _ markdown: String,
        in shell: Shell = .app,
        selector: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Bool {
        let value = try render(
            markdown,
            in: shell,
            then: "!!document.querySelector(\(selector))",
            file: file,
            line: line
        )
        return (value as? Bool) ?? false
    }

    // MARK: - Rendering

    func test_gfmAndExtensions_render() throws {
        let markdown = """
        # Heading

        **bold** ~~struck~~

        | a | b |
        |---|---|
        | 1 | 2 |

        - [x] done

        ```swift
        let x = 1
        ```

        $E = mc^2$

        ```mermaid
        graph LR
          A --> B
        ```
        """

        let probe = """
        (function () {
          var c = document.getElementById('content');
          return JSON.stringify({
            heading: !!c.querySelector('h1'),
            headingId: (c.querySelector('h1') || {}).id || '',
            bold: !!c.querySelector('strong'),
            struck: !!c.querySelector('s, del'),
            table: !!c.querySelector('table'),
            taskCheckbox: !!c.querySelector('li.task-list-item input[type=checkbox]'),
            highlighted: !!c.querySelector('code.language-swift .hljs-keyword'),
            math: !!c.querySelector('.katex'),
            mermaid: !!c.querySelector('svg')
          });
        })()
        """

        let json = try XCTUnwrap(try render(markdown, then: probe) as? String)
        let result = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let flags = try XCTUnwrap(result)

        XCTAssertEqual(flags["heading"] as? Bool, true, "markdown-it")
        XCTAssertEqual(flags["headingId"] as? String, "heading", "GitHub-style heading slug")
        XCTAssertEqual(flags["bold"] as? Bool, true)
        XCTAssertEqual(flags["struck"] as? Bool, true, "GFM strikethrough")
        XCTAssertEqual(flags["table"] as? Bool, true, "GFM table")
        XCTAssertEqual(flags["taskCheckbox"] as? Bool, true, "markdown-it-task-lists")
        XCTAssertEqual(flags["highlighted"] as? Bool, true, "highlight.js")
        XCTAssertEqual(flags["math"] as? Bool, true, "KaTeX")
        XCTAssertEqual(flags["mermaid"] as? Bool, true, "Mermaid")
    }

    func test_scriptTagsInMarkdown_areStripped() throws {
        let value = try render(
            "Hello <script>window.pwned = true;</script> there\n",
            then: "JSON.stringify({script: !!document.querySelector('#content script'), pwned: !!window.pwned})"
        )
        let json = try XCTUnwrap(value as? String)

        XCTAssertTrue(json.contains("\"script\":false"), "DOMPurify should drop the tag")
        XCTAssertTrue(json.contains("\"pwned\":false"), "and it must never have executed")
    }

    func test_eventHandlerAttributes_areStripped() throws {
        let hasHandler = try renderBool(
            "<img src=\"x\" onerror=\"window.pwned = true\">\n",
            selector: "'#content [onerror]'"
        )
        XCTAssertFalse(hasHandler)
    }

    // MARK: - Scroll sync mapping

    func test_blocksCarryTheirSourceLine() throws {
        let markdown = (1...40)
            .map { "## Section \($0)\n\nBody for section \($0).\n" }
            .joined(separator: "\n")

        let probe = """
        (function () {
          var els = document.querySelectorAll('#content [data-source-line]');
          var lines = [];
          for (var i = 0; i < els.length; i++) {
            lines.push(parseInt(els[i].getAttribute('data-source-line'), 10));
          }
          var ascending = lines.every(function (l, i) { return i === 0 || l >= lines[i - 1]; });
          return JSON.stringify({count: lines.length, first: lines[0], ascending: ascending});
        })()
        """

        let json = try XCTUnwrap(try render(markdown, then: probe) as? String)
        let result = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )

        XCTAssertGreaterThan(try XCTUnwrap(result["count"] as? Int), 40, "one anchor per block")
        XCTAssertEqual(result["first"] as? Int, 0)
        XCTAssertEqual(result["ascending"] as? Bool, true)
    }

    func test_scrollToSourceLine_roundTripsThroughCurrentSourceLine() throws {
        let markdown = (1...120)
            .map { "## Section \($0)\n\nBody for section \($0), long enough to wrap.\n" }
            .joined(separator: "\n")

        let probe = """
        (function () {
          var out = [];
          [40, 120, 240].forEach(function (line) {
            window.scrollToSourceLine(line);
            out.push({asked: line, got: window.currentSourceLine()});
          });
          return JSON.stringify(out);
        })()
        """

        let json = try XCTUnwrap(try render(markdown, then: probe) as? String)
        let pairs = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        )

        XCTAssertEqual(pairs.count, 3)
        for pair in pairs {
            let asked = try XCTUnwrap(pair["asked"] as? Int)
            let got = try XCTUnwrap(pair["got"] as? Int)
            XCTAssertEqual(got, asked, accuracy: 2, "line \(asked) should map back to itself")
        }
    }

    // MARK: - Quick Look isolation

    func test_quickLookShell_blocksNetworkAccess() throws {
        // default-src 'none' has to stop the page reaching out; a data: URL is
        // used so the check needs no server and no network.
        let probe = """
        (function () {
          return fetch('data:text/plain,ok')
            .then(function () { window.__connect = 'allowed'; })
            .catch(function () { window.__connect = 'blocked'; });
        })(), 'started'
        """

        _ = try render("# Quick Look\n", in: .quickLook, settleFor: 1.0, then: probe)

        let settled = expectation(description: "fetch settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { settled.fulfill() }
        wait(for: [settled], timeout: 10)

        var verdict: Any?
        let read = expectation(description: "verdict read")
        loader.webView.evaluateJavaScript("window.__connect || 'pending'") { value, _ in
            verdict = value
            read.fulfill()
        }
        wait(for: [read], timeout: 30)

        XCTAssertEqual(verdict as? String, "blocked", "the Quick Look CSP must be in force")
    }

    func test_appShell_isNotUnderTheQuickLookPolicy() throws {
        // The counterpart to the check above: if the app shell also blocked
        // connections, that test would pass for the wrong reason.
        let probe = """
        (function () {
          return fetch('data:text/plain,ok')
            .then(function () { window.__connect = 'allowed'; })
            .catch(function () { window.__connect = 'blocked'; });
        })(), 'started'
        """

        _ = try render("# App\n", in: .app, settleFor: 1.0, then: probe)

        let settled = expectation(description: "fetch settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { settled.fulfill() }
        wait(for: [settled], timeout: 10)

        var verdict: Any?
        let read = expectation(description: "verdict read")
        loader.webView.evaluateJavaScript("window.__connect || 'pending'") { value, _ in
            verdict = value
            read.fulfill()
        }
        wait(for: [read], timeout: 30)

        XCTAssertEqual(verdict as? String, "allowed")
    }

    func test_bothShellsRenderTheSameDocument() throws {
        let markdown = "# Title\n\n**bold**\n\n```swift\nlet x = 1\n```\n"
        let probe = """
        document.getElementById('content').innerHTML.replace(/id="task-item-\\d+"/g, '')
        """

        let fromApp = try XCTUnwrap(try render(markdown, in: .app, then: probe) as? String)

        loader = Loader()
        let fromQuickLook = try XCTUnwrap(try render(markdown, in: .quickLook, then: probe) as? String)

        XCTAssertEqual(fromApp, fromQuickLook, "the shells must not drift apart")
    }
}
