# markdown-prism Status

> Last updated: 2026-08-02
> Status: shipping — signed, notarized, distributed via the `hulryung/tap` Homebrew cask

All four planned phases (viewer, editor, Quick Look, polish) are done. This
document describes how the app is put together today and what is still open;
per-release detail lives in the git history.

---

## Architecture

Native shell, web renderer:

```
[.md file] ──> MarkdownDocument ──> ContentView ──┬──> EditorView   (NSTextView + MarkdownHighlighter)
                                                  └──> PreviewView  (WKWebView)
                                                             │
                                    evaluateJavaScript("renderMarkdown(...)")
                                                             ▼
                                        preview.html ──> js/preview.js
                                                             │
                            ┌────────────┬───────────┬───────┴──────┬──────────┐
                            ▼            ▼           ▼              ▼          ▼
                       markdown-it  highlight.js   KaTeX        Mermaid    DOMPurify
```

- **Swift → JS**: markdown is JSON-encoded and passed to `window.renderMarkdown`.
- **JS → Swift**: `WKScriptMessageHandler` for link clicks and preview scroll position.
- **Rendering logic** lives in `Resources/js/preview.js`, shared by two shells:
  - `preview.html` — in-app preview, allows remote images.
  - `preview-quicklook.html` — same page under a strict Content-Security-Policy,
    since a Quick Look preview renders whatever file Finder points at.
- **Quick Look** (`Sources/QuickLookExtension`) loads that shell straight out of
  the bundle; nothing is copied per preview.
- All JS/CSS is vendored under `Resources/vendor/`. The app renders offline.

## Layout

```
Sources/MarkdownPrism/
  App/         MarkdownPrismApp, AppDelegate, menu commands
  Views/       ContentView, EditorView, PreviewView, FindBarView
  Models/      MarkdownDocument, FileWatcher, MarkdownHighlighter, ZoomState,
               RecentDocumentsManager, SecurityScopedAccess, LineIndex, ScrollSync,
               DefaultAppHelper
  Resources/   preview.html, preview-quicklook.html, js/, css/, vendor/
Sources/QuickLookExtension/
Tests/MarkdownPrismTests/
```

## Implemented

- GFM rendering: tables, task lists, strikethrough, autolinks, emoji
- Syntax highlighting (highlight.js), LaTeX (KaTeX), Mermaid diagrams
- Split-pane editor with debounced live preview and markdown syntax highlighting
- Two-way scroll sync between editor and preview
- Find and replace, with regex, across both panes
- Quick Look extension
- File watching with reload prompts, atomic saves, encoding detection
- Open Recent backed by security-scoped bookmarks, zoom, full-width toggle,
  internal heading links, "set as default app"

## Open items

| Area | Item |
|------|------|
| Architecture | `OpenFileState` (`isModified`, `saveHandler`) is shared by every window, so restored multi-window sessions can cross wires. A per-document model or `DocumentGroup` would fix it and unlock tabs. |
| Files | Saving always writes UTF-8, discarding the encoding `MarkdownDocument` detected. |
| Files | The CLI argument path checks `fileExists` before security-scoped access begins (`MarkdownPrismApp.swift`). |
| Editor | No line numbers. |
| UI | No preferences panel (theme, font), no localization — the app is English-only while the site ships a Korean page. |
| Testing | `js/preview.js` has no automated tests; the rendering pipeline is only covered by hand. |

## Release

- Version lives once, as `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in
  `project.yml`. Both `Info.plist` files are generated from it by xcodegen — do
  not edit them by hand.
- `scripts/build-dmg.sh` builds and signs the Release app and packages
  `build/MarkdownPrism-<version>.dmg`. Set `NOTARY_PROFILE` to a notarytool
  keychain profile to notarize and staple; without it the DMG is signed but
  Gatekeeper rejects it on other Macs. Two submissions run: the app is
  notarized and stapled before packaging so the ticket ships inside the
  bundle, then the DMG is notarized and stapled as well.
- `scripts/validate-dmg.sh <dmg>` checks the app bundle name inside the DMG.
- `scripts/update-cask.sh <dmg>` regenerates the Homebrew cask, reading the
  version from `project.yml` and the app name from the DMG.
- CI (`.github/workflows/ci.yml`) runs `swift build`, `swift test`, and an
  xcodegen + xcodebuild Release build on every push and pull request.
