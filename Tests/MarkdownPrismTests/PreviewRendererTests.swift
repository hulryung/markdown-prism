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
    ///
    /// Passing `baseline` renders the rich diff of the two instead, which is the
    /// only difference between exercising `renderMarkdown` and `renderDiff`.
    private func render(
        _ markdown: String,
        comparedWith baseline: String? = nil,
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
        let call: String
        if let baseline {
            let encodedBaseline = try XCTUnwrap(
                String(data: JSONEncoder().encode(baseline), encoding: .utf8)
            )
            call = "window.renderDiff(\(encodedBaseline), \(encoded)); 1"
        } else {
            call = "window.renderMarkdown(\(encoded)); 1"
        }

        let rendered = expectation(description: "markdown rendered")
        var renderError: Error?
        loader.webView.evaluateJavaScript(call) { _, error in
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

    // MARK: - Rich diff

    /// Counts the diff markup a rendered comparison produced.
    private static let diffCensus = """
    (function () {
      var c = document.getElementById('content');
      function text(selector) {
        var el = c.querySelector(selector);
        return el ? el.textContent : '';
      }
      return JSON.stringify({
        added: c.querySelectorAll('.diff-block-added').length,
        removed: c.querySelectorAll('.diff-block-removed').length,
        changed: c.querySelectorAll('.diff-block-changed').length,
        insertions: c.querySelectorAll('ins.diff-words-added').length,
        deletions: c.querySelectorAll('del.diff-words-removed').length,
        firstInsertion: text('ins.diff-words-added'),
        firstDeletion: text('del.diff-words-removed'),
        paragraphs: c.querySelectorAll('p').length,
        listItems: c.querySelectorAll('li').length,
        lists: c.querySelectorAll('ul').length,
        preBlocks: c.querySelectorAll('pre').length,
        strong: c.querySelectorAll('strong').length,
        math: c.querySelectorAll('.katex').length
      });
    })()
    """

    private func census(
        _ markdown: String,
        comparedWith baseline: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let json = try XCTUnwrap(
            try render(markdown, comparedWith: baseline, then: Self.diffCensus, file: file, line: line) as? String
        )
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
    }

    func test_diffOfAnUnchangedDocument_marksNothing() throws {
        let markdown = "# Spec\n\nThe body.\n\n- one\n- two\n"
        let result = try census(markdown, comparedWith: markdown)

        XCTAssertEqual(result["added"] as? Int, 0)
        XCTAssertEqual(result["removed"] as? Int, 0)
        XCTAssertEqual(result["changed"] as? Int, 0)
        XCTAssertEqual(result["insertions"] as? Int, 0)
        XCTAssertEqual(result["deletions"] as? Int, 0)
    }

    func test_diffOfAnAddedParagraph_marksOnlyThatBlock() throws {
        let result = try census(
            "# Spec\n\nFirst.\n\nSecond.\n",
            comparedWith: "# Spec\n\nFirst.\n"
        )

        XCTAssertEqual(result["added"] as? Int, 1)
        XCTAssertEqual(result["removed"] as? Int, 0)
        XCTAssertEqual(result["paragraphs"] as? Int, 2)
    }

    func test_diffOfARemovedParagraph_keepsItVisibleAsRemoved() throws {
        let result = try census(
            "# Spec\n\nFirst.\n",
            comparedWith: "# Spec\n\nFirst.\n\nSecond.\n"
        )

        XCTAssertEqual(result["added"] as? Int, 0)
        XCTAssertEqual(result["removed"] as? Int, 1)
        XCTAssertEqual(result["paragraphs"] as? Int, 2, "the removed paragraph is still shown")
    }

    /// The point of a rich diff: an edited sentence stays one paragraph, with
    /// the words that changed marked inside it.
    func test_diffOfAnEditedSentence_marksWordsInsideOneParagraph() throws {
        let result = try census(
            "The spec says beta.\n",
            comparedWith: "The spec says alpha.\n"
        )

        XCTAssertEqual(result["paragraphs"] as? Int, 1, "not replaced by two whole blocks")
        XCTAssertEqual(result["added"] as? Int, 0)
        XCTAssertEqual(result["removed"] as? Int, 0)
        XCTAssertEqual(result["changed"] as? Int, 1)
        // The full stop survives: punctuation is diffed as its own token, so
        // adding a comma mid-sentence does not make the rest look rewritten.
        XCTAssertEqual(result["firstDeletion"] as? String, "alpha")
        XCTAssertEqual(result["firstInsertion"] as? String, "beta")
    }

    /// Punctuation changes on their own must still show, and must not drag the
    /// words on either side of them into the difference.
    func test_diffOfAnAddedComma_marksOnlyThePunctuation() throws {
        let result = try census(
            "It supports Visa, Mastercard and Amex.\n",
            comparedWith: "It supports Visa and Amex.\n"
        )

        XCTAssertEqual(result["paragraphs"] as? Int, 1)
        XCTAssertEqual(result["deletions"] as? Int, 0, "nothing was actually removed")
        XCTAssertEqual(result["firstInsertion"] as? String, ", Mastercard")
    }

    func test_diffOfAnEditedListItem_staysScopedToThatItem() throws {
        let result = try census(
            "- one\n- two edited\n- three\n",
            comparedWith: "- one\n- two\n- three\n"
        )

        XCTAssertEqual(result["lists"] as? Int, 1, "the list is refined, not replaced")
        XCTAssertEqual(result["listItems"] as? Int, 3)
        XCTAssertEqual(result["added"] as? Int, 0)
        XCTAssertEqual(result["removed"] as? Int, 0)
        XCTAssertEqual(result["insertions"] as? Int, 1)
    }

    /// Word-diffing a code fence would scramble it, and a Mermaid source block
    /// only renders if it reaches the renderer intact.
    func test_diffOfAnEditedCodeFence_replacesTheWholeBlock() throws {
        let result = try census(
            "```swift\nlet x = 2\n```\n",
            comparedWith: "```swift\nlet x = 1\n```\n"
        )

        XCTAssertEqual(result["preBlocks"] as? Int, 2)
        XCTAssertEqual(result["added"] as? Int, 1)
        XCTAssertEqual(result["removed"] as? Int, 1)
        XCTAssertEqual(result["insertions"] as? Int, 0, "no word markup inside a fence")
        XCTAssertEqual(result["deletions"] as? Int, 0)
    }

    /// Splitting `$...$` across an <ins> boundary leaves KaTeX with an
    /// unterminated expression, so blocks carrying math are replaced whole.
    func test_diffOfAnEditedMathParagraph_keepsTheMathRenderable() throws {
        let result = try census(
            "Energy is $E = mc^2$ there.\n",
            comparedWith: "Energy is $E = mc^2$ here.\n"
        )

        XCTAssertEqual(result["math"] as? Int, 2, "both versions still render")
        XCTAssertEqual(result["insertions"] as? Int, 0)
        XCTAssertEqual(result["added"] as? Int, 1)
        XCTAssertEqual(result["removed"] as? Int, 1)
    }

    func test_diffOfAnEditedEmphasisedSentence_keepsTheEmphasis() throws {
        let result = try census(
            "This is **very** important indeed.\n",
            comparedWith: "This is **very** important.\n"
        )

        XCTAssertEqual(result["strong"] as? Int, 1, "inline markup survives the word diff")
        XCTAssertEqual(result["changed"] as? Int, 1)
        XCTAssertGreaterThan(try XCTUnwrap(result["insertions"] as? Int), 0)
    }

    /// Scroll sync interpolates between source-line anchors, so the anchors left
    /// behind by a diff have to stay in document order. Removed blocks describe
    /// lines of a document that no longer exists and must not contribute any.
    func test_diffKeepsSourceLineAnchorsInOrder() throws {
        let baseline = (1...12)
            .map { "## Section \($0)\n\nBody for section \($0).\n" }
            .joined(separator: "\n")
        let edited = (1...12)
            .map { $0 == 5 ? "## Section 5\n\nRewritten body.\n\nAnd an extra paragraph.\n" : "## Section \($0)\n\nBody for section \($0).\n" }
            .joined(separator: "\n")

        let probe = """
        (function () {
          var els = document.querySelectorAll('#content [data-source-line]');
          var lines = [];
          for (var i = 0; i < els.length; i++) {
            lines.push(parseInt(els[i].getAttribute('data-source-line'), 10));
          }
          var ascending = lines.every(function (l, i) { return i === 0 || l >= lines[i - 1]; });
          var removedWithLines = document.querySelectorAll('#content .diff-block-removed[data-source-line]').length;
          return JSON.stringify({
            count: lines.length,
            ascending: ascending,
            removedWithLines: removedWithLines
          });
        })()
        """

        let json = try XCTUnwrap(
            try render(edited, comparedWith: baseline, then: probe) as? String
        )
        let result = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )

        XCTAssertGreaterThan(try XCTUnwrap(result["count"] as? Int), 12)
        XCTAssertEqual(result["ascending"] as? Bool, true)
        XCTAssertEqual(result["removedWithLines"] as? Int, 0)
    }

    /// The word diff builds markup by hand, so the invariant that keeps it safe
    /// is checked directly: strip the annotations back out and what is left has
    /// to be exactly the new side.
    func test_wordDiff_rebuildsExactlyTheNewMarkup() throws {
        let probe = """
        (function () {
          var cases = [
            ['<em>a</em> x <strong>c</strong>', '<em>a</em> b <strong>c</strong> d'],
            ['plain text here', 'plain text there'],
            ['', 'everything is new'],
            ['everything goes away', ''],
            ['<a href="#x">link</a> tail', '<a href="#x">link</a> different tail'],
            ['same', 'same']
          ];
          var results = [];
          cases.forEach(function (pair) {
            var merged = window.MarkdownDiff.mergeWords(pair[0], pair[1]);
            var stripped = document.createElement('div');
            stripped.innerHTML = merged;
            Array.prototype.forEach.call(
              stripped.querySelectorAll('del.diff-words-removed'),
              function (el) { el.parentNode.removeChild(el); }
            );
            Array.prototype.forEach.call(
              stripped.querySelectorAll('ins.diff-words-added'),
              function (el) {
                while (el.firstChild) el.parentNode.insertBefore(el.firstChild, el);
                el.parentNode.removeChild(el);
              }
            );
            var reference = document.createElement('div');
            reference.innerHTML = pair[1];
            results.push({ rebuilt: stripped.innerHTML, expected: reference.innerHTML });
          });
          return JSON.stringify(results);
        })()
        """

        let json = try XCTUnwrap(try render("", then: probe) as? String)
        let results = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
        )

        XCTAssertEqual(results.count, 6)
        for result in results {
            XCTAssertEqual(result["rebuilt"], result["expected"])
        }
    }
}
