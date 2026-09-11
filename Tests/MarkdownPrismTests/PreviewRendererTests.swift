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

    // Issue #13: word-level assertions alone missed whole-list markers and
    // false changes caused by the task-list plugin's generated checkbox IDs.
    private func listDiffResults(_ script: String, in shell: Shell = .app) throws -> [[String: Any]] {
        let json = try XCTUnwrap(try render("", in: shell, settleFor: 0.1, then: script) as? String)
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]]
        )
    }

    func test_listDiffUnchangedContent_marksNothingEvenAfterLineShifts() throws {
        let probe = #"""
        (function () {
          var lists = [
            '- Alpha\n- Beta\n',
            '1. Alpha\n2. Beta\n',
            '- [ ] Alpha\n- [x] Beta\n',
            '1. Outer **label**\n   - [ ] Nested task\n2. Other item\n',
            '- Outer label\n  - [x] Nested task\n- Other item\n'
          ];
          return JSON.stringify(lists.map(function (list) {
            window.renderDiff(list, list);
            var unchanged = document.querySelectorAll('#content .diff-block').length;
            var count = window.changeSummary().count;
            window.renderDiff('Intro.\n\n' + list, 'Intro.\n\nInserted paragraph.\n\n' + list);
            return {
              markdown: list, unchanged: unchanged, count: count,
              shiftedListMarks: document.querySelectorAll('#content li.diff-block, #content ul.diff-block, #content ol.diff-block').length,
              shiftedChanges: window.changeSummary().count
            };
          }));
        })()
        """#
        for shell in [Shell.app, .quickLook] {
            for result in try listDiffResults(probe, in: shell) {
                let context = "\(shell): \(result["markdown"] ?? "")"
                XCTAssertEqual(result["unchanged"] as? Int, 0, context)
                XCTAssertEqual(result["count"] as? Int, 0, context)
                XCTAssertEqual(result["shiftedListMarks"] as? Int, 0, context)
                XCTAssertEqual(result["shiftedChanges"] as? Int, 1, context)
            }
        }
    }

    func test_listDiffSeparatedEdits_scopeMarkersNavigationAndRulerToItems() throws {
        let probe = #"""
        (function () {
          var formats = [
            ['- ', '\n'], ['1. ', '\n'], ['- [ ] ', '\n'],
            ['1. ', '\n\n'], ['   - ', '\n']
          ];
          return JSON.stringify(formats.map(function (format) {
            var before = ['Alpha item', 'Beta item', 'Gamma item', 'Delta item'];
            var after = ['Alpha item edited', 'Beta item', 'Gamma item', 'Delta item edited'];
            function markdown(items) {
              return items.map(function (item) { return format[0] + item; }).join(format[1]) + '\n';
            }
            window.renderDiff(markdown(before), markdown(after));
            var c = document.getElementById('content');
            var stops = [];
            for (var i = 0; i < 3; i++) {
              window.nextChange();
              stops.push(c.querySelector('.diff-change-current').textContent.trim());
            }
            window.previousChange();
            var marked = Array.from(c.querySelectorAll('.diff-block'));
            var ticks = Array.from(document.querySelectorAll('#diff-ruler .diff-ruler-tick'));
            var documentHeight = document.documentElement.scrollHeight;
            return {
              count: window.changeSummary().count, ticks: ticks.length, stops: stops,
              previous: c.querySelector('.diff-change-current').textContent.trim(),
              listMarks: c.querySelectorAll('ul.diff-block, ol.diff-block').length,
              marked: marked.length,
              unchangedItemMarks: Array.from(c.querySelectorAll('li')).slice(1, 3).filter(function (li) {
                return li.matches('.diff-block') || li.querySelector('.diff-block');
              }).length,
              heightsMatch: ticks.length === marked.length && ticks.every(function (tick, index) {
                return Math.abs(parseFloat(tick.style.height) * documentHeight / 100 - marked[index].getBoundingClientRect().height) < 1;
              })
            };
          }));
        })()
        """#
        for result in try listDiffResults(probe) {
            XCTAssertEqual(result["count"] as? Int, 2)
            XCTAssertEqual(result["ticks"] as? Int, 2)
            XCTAssertEqual(result["listMarks"] as? Int, 0)
            XCTAssertEqual(result["marked"] as? Int, 2)
            XCTAssertEqual(result["unchangedItemMarks"] as? Int, 0)
            XCTAssertEqual(result["heightsMatch"] as? Bool, true)
            XCTAssertEqual(result["stops"] as? [String], ["Alpha item edited", "Delta item edited", "Alpha item edited"])
            XCTAssertEqual(result["previous"] as? String, "Delta item edited")
        }
    }

    func test_listDiffAdjacentEdits_formOneNavigationStop() throws {
        for separator in ["\n", "\n\n"] {
            let before = ["1. Alpha item", "2. Beta item", "3. Gamma item"].joined(separator: separator)
            let after = ["1. Alpha item edited", "2. Beta item edited", "3. Gamma item"].joined(separator: separator)
            let result = try changes(after, comparedWith: before)
            XCTAssertEqual(result["count"] as? Int, 1)
            XCTAssertEqual(result["ticks"] as? Int, 1)
        }
    }

    func test_listDiffInsertedAndRemovedItems_markOnlyThoseItems() throws {
        let probe = #"""
        (function () {
          return JSON.stringify(['- ', '1. ', '- [ ] '].flatMap(function (prefix) {
            var before = prefix + 'Alpha item\n' + prefix + 'Gamma item\n';
            var after = prefix + 'Alpha item\n' + prefix + 'Beta item\n' + prefix + 'Gamma item\n';
            return [[before, after, 'added'], [after, before, 'removed']].map(function (sample) {
              window.renderDiff(sample[0], sample[1]);
              var marked = Array.from(document.querySelectorAll('#content .diff-block'));
              return {
                count: window.changeSummary().count, marked: marked.length,
                tag: marked[0] && marked[0].tagName,
                expectedKind: marked[0] && marked[0].classList.contains('diff-block-' + sample[2]),
                text: marked[0] && marked[0].textContent.trim(),
                removedAnchors: document.querySelectorAll('#content .diff-block-removed[data-source-line], #content .diff-block-removed [data-source-line]').length,
                linkedLabels: Array.from(document.querySelectorAll('#content label[for]')).every(function (label) {
                  return !!document.getElementById(label.htmlFor);
                })
              };
            });
          }));
        })()
        """#
        for result in try listDiffResults(probe) {
            XCTAssertEqual(result["count"] as? Int, 1)
            XCTAssertEqual(result["marked"] as? Int, 1)
            XCTAssertEqual(result["tag"] as? String, "LI")
            XCTAssertEqual(result["text"] as? String, "Beta item")
            XCTAssertEqual(result["expectedKind"] as? Bool, true)
            XCTAssertEqual(result["removedAnchors"] as? Int, 0)
            XCTAssertEqual(result["linkedLabels"] as? Bool, true)
        }
    }

    func test_listDiffSemanticChanges_remainVisible() throws {
        let probe = #"""
        (function () {
          var samples = [
            ['- [ ] Task\n', '- [x] Task\n', 'input:checked'],
            ['- [Link](https://example.com/old)\n', '- [Link](https://example.com/new)\n', 'a[href="https://example.com/new"]'],
            ['1. Alpha\n2. Beta\n', '3. Alpha\n4. Beta\n', 'ol[start="3"]'],
            ['- <span id="old">Anchor</span>\n', '- <span id="new">Anchor</span>\n', 'span[id="new"]']
          ];
          return JSON.stringify(samples.map(function (sample) {
            window.renderDiff(sample[0], sample[1]);
            return {
              count: window.changeSummary().count,
              currentValue: !!document.querySelector('#content ' + sample[2])
            };
          }));
        })()
        """#
        for result in try listDiffResults(probe) {
            XCTAssertEqual(result["count"] as? Int, 1)
            XCTAssertEqual(result["currentValue"] as? Bool, true)
        }
    }

    func test_listDiffNestedEdits_preserveParentTextAndInlineMarkup() throws {
        let probe = #"""
        (function () {
          var samples = [
            ['1. Outer **label**\n   - [ ] Nested task\n2. Other item\n',
             '1. Outer **label**\n   - [ ] Nested task edited\n2. Other item\n'],
            ['- Outer **label**\n  - Nested item\n', '- Outer **label** edited\n  - Nested item\n']
          ];
          return JSON.stringify(samples.map(function (sample) {
            var c = document.getElementById('content');
            window.renderMarkdown(sample[1]);
            var expected = c.innerText.replace(/\s+/g, ' ').trim();
            window.renderDiff(sample[0], sample[1]);
            return {
              expected: expected, actual: c.innerText.replace(/\s+/g, ' ').trim(),
              emphasis: c.querySelector('strong') && c.querySelector('strong').textContent,
              count: window.changeSummary().count,
              marked: c.querySelectorAll('.diff-block').length
            };
          }));
        })()
        """#
        for result in try listDiffResults(probe) {
            XCTAssertEqual(result["actual"] as? String, result["expected"] as? String)
            XCTAssertEqual(result["emphasis"] as? String, "label")
            XCTAssertEqual(result["count"] as? Int, 1)
            XCTAssertEqual(result["marked"] as? Int, 1)
        }
    }

    func test_listDiffGutters_preserveIndentationAndStayOutsideListMarkers() throws {
        let probe = #"""
        (function () {
          var c = document.getElementById('content');
          return JSON.stringify(['- ', '1. ', '- [ ] '].map(function (prefix) {
            var before = prefix + 'Alpha item\n' + prefix + 'Beta item\n';
            var after = prefix + 'Alpha item edited\n' + prefix + 'Beta item\n';
            window.renderMarkdown(after);
            var plainX = c.querySelector('li').getBoundingClientRect().left;
            var plainPadding = getComputedStyle(c.querySelector('ul,ol')).paddingLeft;
            window.renderDiff(before, after);
            var item = c.querySelector('li');
            var gutter = document.querySelector('#diff-gutter .diff-gutter-mark');
            var mark = c.querySelector('.diff-block');
            var gutterRect = gutter && gutter.getBoundingClientRect();
            var markRect = mark && mark.getBoundingClientRect();
            var listLeft = c.querySelector('ul,ol').getBoundingClientRect().left;
            var result = {
              plainX: plainX, diffX: item.getBoundingClientRect().left,
              plainPadding: plainPadding, diffPadding: getComputedStyle(c.querySelector('ul,ol')).paddingLeft,
              gutterOutside: !!gutterRect && gutterRect.right <= listLeft,
              gutterMatchesItem: !!gutterRect && Math.abs(gutterRect.top - markRect.top) < 1 && Math.abs(gutterRect.height - markRect.height) < 1
            };
            window.renderMarkdown(after);
            var strip = document.getElementById('diff-gutter');
            result.cleared = !strip || strip.style.display === 'none' || strip.children.length === 0;
            return result;
          }));
        })()
        """#
        for result in try listDiffResults(probe) {
            XCTAssertEqual(result["diffX"] as? Double, result["plainX"] as? Double)
            XCTAssertEqual(result["diffPadding"] as? String, result["plainPadding"] as? String)
            XCTAssertEqual(result["gutterOutside"] as? Bool, true)
            XCTAssertEqual(result["gutterMatchesItem"] as? Bool, true)
            XCTAssertEqual(result["cleared"] as? Bool, true)
        }
    }

    func test_listDiffWholeListAdditionAndRemoval_usesOneMarker() throws {
        let probe = #"""
        (function () {
          var list = '- [ ] Alpha\n- [x] Beta\n';
          return JSON.stringify([['', list, 'added'], [list, '', 'removed']].map(function (sample) {
            window.renderDiff(sample[0], sample[1]);
            var c = document.getElementById('content');
            return {
              count: window.changeSummary().count,
              marks: c.querySelectorAll('.diff-block').length,
              wholeList: !!c.querySelector('ul.diff-block-' + sample[2]),
              items: c.querySelectorAll('li').length,
              gutters: document.querySelectorAll('#diff-gutter .diff-gutter-mark').length
            };
          }));
        })()
        """#
        for result in try listDiffResults(probe) {
            XCTAssertEqual(result["count"] as? Int, 1)
            XCTAssertEqual(result["marks"] as? Int, 1)
            XCTAssertEqual(result["wholeList"] as? Bool, true)
            XCTAssertEqual(result["items"] as? Int, 2)
            XCTAssertEqual(result["gutters"] as? Int, 1)
        }
    }

    func test_listDiffMermaidReplacement_keepsMarkersAfterAsyncRendering() throws {
        let before = "- Diagram:\n  ```mermaid\n  graph LR\n    A --> B\n  ```\n"
        let after = before.replacingOccurrences(of: "A --> B", with: "A --> C")
        let encodedBefore = try XCTUnwrap(String(data: JSONEncoder().encode(before), encoding: .utf8))
        let encodedAfter = try XCTUnwrap(String(data: JSONEncoder().encode(after), encoding: .utf8))
        let probe = """
        (function () {
          function census() {
            var c = document.getElementById('content');
            return {
              count: window.changeSummary().count,
              removed: c.querySelectorAll('.diff-block-removed svg').length,
              added: c.querySelectorAll('.diff-block-added svg').length,
              listMarks: c.querySelectorAll('ul.diff-block, li.diff-block').length,
              removedAnchors: c.querySelectorAll('.diff-block-removed[data-source-line]').length
            };
          }
          var fresh = census();
          window.renderDiff(\(encodedBefore), \(encodedAfter));
          return JSON.stringify([fresh, census()]);
        })()
        """
        let json = try XCTUnwrap(try render(after, comparedWith: before, then: probe) as? String)
        let results = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Int]]
        )
        for result in results {
            XCTAssertEqual(result["count"], 1)
            XCTAssertEqual(result["removed"], 1)
            XCTAssertEqual(result["added"], 1)
            XCTAssertEqual(result["listMarks"], 0)
            XCTAssertEqual(result["removedAnchors"], 0)
        }
    }

    func test_listDiffLayoutChanges_repositionGutterAndRuler() throws {
        // WebKit pauses animation frames in a detached view. Give this one
        // layout test a window so it exercises real ResizeObserver/frame timing.
        let application = NSApplication.shared
        let previousPolicy = application.activationPolicy()
        application.setActivationPolicy(.accessory)
        // XCTest runs the Foundation loop, not NSApplication's event loop.
        // Deliver window visibility events so WebKit resumes animation frames.
        let events = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            while let event = application.nextEvent(matching: .any, until: .distantPast,
                                                     inMode: .default, dequeue: true) {
                application.sendEvent(event)
            }
            application.updateWindows()
        }
        let window = NSWindow(contentRect: loader.webView.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = loader.webView
        window.orderFront(nil)
        defer {
            events.invalidate()
            window.orderOut(nil)
            window.contentView = nil
            application.setActivationPolicy(previousPolicy)
        }
        application.activate(ignoringOtherApps: true)
        let before = "1. Alpha item with enough words to wrap when the preview becomes narrow.\n2. Beta item\n3. Gamma item\n"
        let after = before.replacingOccurrences(of: "Gamma item", with: "Gamma item edited")
        _ = try render(after, comparedWith: before, then: "1")

        let finished = expectation(description: "layout and overlays updated")
        var results: [[String: Bool]]?
        var scriptError: Error?
        loader.webView.callAsyncJavaScript(#"""
        var results = [];
        var content = document.getElementById('content');
        var changes = [
          function () { window.setTypography('Georgia', 23); },
          function () { content.style.width = '320px'; },
          function () { content.style.paddingTop = '80px'; },
          function () { content.style.width = ''; window.setFullWidth(true); }
        ];
        for (var change of changes) {
          change();
          // ResizeObserver delivers after layout and schedules the next frame.
          for (var i = 0; i < 3; i++) await new Promise(requestAnimationFrame);
          var block = content.querySelector('.diff-block').getBoundingClientRect();
          var gutter = document.querySelector('#diff-gutter .diff-gutter-mark').getBoundingClientRect();
          var tick = document.querySelector('#diff-ruler .diff-ruler-tick');
          var height = document.documentElement.scrollHeight;
          results.push({
            top: Math.abs(gutter.top - block.top) < 1,
            height: Math.abs(gutter.height - block.height) < 1,
            left: Math.abs(gutter.left - (content.getBoundingClientRect().left + parseFloat(getComputedStyle(content).paddingLeft) - 16)) < 1,
            ruler: Math.abs(parseFloat(tick.style.top) * height / 100 - (block.top + window.scrollY)) < 1
          });
        }
        return results;
        """#, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let value): results = value as? [[String: Bool]]
            case .failure(let error): scriptError = error
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 15)
        XCTAssertNil(scriptError)
        let checks = try XCTUnwrap(results)
        XCTAssertEqual(checks.count, 4)
        for (index, check) in checks.enumerated() {
            XCTAssertTrue(check.values.allSatisfy { $0 }, "Layout change \(index): \(check)")
        }
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

    // MARK: - Moving between changes

    private static let changeCensus = """
    (function () {
      var ticks = document.querySelectorAll('#diff-ruler .diff-ruler-tick');
      var ruler = document.getElementById('diff-ruler');
      return JSON.stringify({
        count: window.changeSummary().count,
        current: window.changeSummary().current,
        ticks: ticks.length,
        kinds: Array.prototype.map.call(ticks, function (t) {
          return t.className.replace('diff-ruler-tick ', '');
        }),
        rulerShown: !!ruler && ruler.style.display !== 'none'
      });
    })()
    """

    private func changes(
        _ markdown: String,
        comparedWith baseline: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let json = try XCTUnwrap(
            try render(markdown, comparedWith: baseline, then: Self.changeCensus, file: file, line: line) as? String
        )
        return try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
    }

    func test_separatedEdits_countAsOneChangeEach() throws {
        let result = try changes(
            "# Spec\n\nAlpha.\n\nBeta edited.\n\nGamma.\n\nDelta edited.\n\nEpsilon.\n",
            comparedWith: "# Spec\n\nAlpha.\n\nBeta.\n\nGamma.\n\nDelta.\n\nEpsilon.\n"
        )

        XCTAssertEqual(result["count"] as? Int, 2)
        XCTAssertEqual(result["ticks"] as? Int, 2, "one tick per change")
        XCTAssertEqual(result["rulerShown"] as? Bool, true)
    }

    /// Adjacent marked blocks are one hunk, the same unit git reports. Stopping
    /// twice inside a single highlighted band would read as a bug.
    func test_adjacentEdits_countAsASingleChange() throws {
        let result = try changes(
            "One.\n\nTwo changed.\n\nThree changed.\n",
            comparedWith: "One.\n\nTwo.\n\nThree.\n"
        )

        XCTAssertEqual(result["count"] as? Int, 1)
        XCTAssertEqual(result["ticks"] as? Int, 1)
    }

    func test_anUnchangedDocument_hasNoChangesToStepThroughAndNoRuler() throws {
        let markdown = "# Spec\n\nThe body.\n"
        let result = try changes(markdown, comparedWith: markdown)

        XCTAssertEqual(result["count"] as? Int, 0)
        XCTAssertEqual(result["ticks"] as? Int, 0)
        XCTAssertEqual(result["rulerShown"] as? Bool, false)
    }

    /// A run holding both a removal and what replaced it is a revision, not two
    /// separate things, and the ruler colours it as one.
    func test_theRulerColoursEachChangeByWhatItIs() throws {
        let result = try changes(
            "Kept.\n\n```\nnew code\n```\n\nAlso kept.\n\nAdded paragraph.\n",
            comparedWith: "Kept.\n\n```\nold code\n```\n\nAlso kept.\n"
        )

        let kinds = try XCTUnwrap(result["kinds"] as? [String])
        XCTAssertEqual(kinds, ["diff-ruler-changed", "diff-ruler-added"])
    }

    func test_steppingThroughChanges_wrapsAroundAndReportsPosition() throws {
        let probe = """
        (function () {
          var steps = [];
          steps.push(window.nextChange());
          steps.push(window.nextChange());
          steps.push(window.nextChange());
          steps.push(window.previousChange());
          steps.push({ marked: document.querySelectorAll('.diff-change-current').length });
          return JSON.stringify(steps);
        })()
        """

        let json = try XCTUnwrap(
            try render(
                "# Spec\n\nAlpha.\n\nBeta edited.\n\nGamma.\n\nDelta edited.\n\nEpsilon.\n",
                comparedWith: "# Spec\n\nAlpha.\n\nBeta.\n\nGamma.\n\nDelta.\n\nEpsilon.\n",
                then: probe
            ) as? String
        )
        let steps = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Int]]
        )

        XCTAssertEqual(steps[0]["current"], 1)
        XCTAssertEqual(steps[1]["current"], 2)
        XCTAssertEqual(steps[2]["current"], 1, "past the last change comes the first")
        XCTAssertEqual(steps[3]["current"], 2, "and back again from the first")
        XCTAssertEqual(steps[0]["count"], 2)
        XCTAssertGreaterThan(try XCTUnwrap(steps[4]["marked"]), 0, "the current change is marked")
    }

    /// Leaving the comparison has to take the ruler with it, or a plain document
    /// keeps a strip of ticks pointing at blocks that are no longer marked.
    func test_renderingPlainlyAfterADiff_clearsTheChangesAndTheRuler() throws {
        let probe = """
        (function () {
          window.renderMarkdown('# Plain\\n\\nNothing to compare.\\n');
          var ruler = document.getElementById('diff-ruler');
          return JSON.stringify({
            count: window.changeSummary().count,
            rulerShown: !!ruler && ruler.style.display !== 'none',
            marked: document.querySelectorAll('.diff-block, .diff-change-current').length
          });
        })()
        """

        let json = try XCTUnwrap(
            try render("One.\n\nTwo changed.\n", comparedWith: "One.\n\nTwo.\n", then: probe) as? String
        )
        let result = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )

        XCTAssertEqual(result["count"] as? Int, 0)
        XCTAssertEqual(result["rulerShown"] as? Bool, false)
        XCTAssertEqual(result["marked"] as? Int, 0)
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
