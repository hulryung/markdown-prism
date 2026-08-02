# Markdown Prism

> **Homepage:** [prism.huconn.xyz](https://prism.huconn.xyz)

A native macOS Markdown viewer & editor with live preview, Quick Look support, and rich rendering.

![Markdown Prism editor with code, math, and diagrams](docs/assets/images/hero.png)

## Features

- **Live Preview** — Split-pane editor with real-time rendered preview
- **Tabs & Windows** — Open as many documents as you like, in windows or native tabs
- **Scroll Sync** — Editor and preview follow each other, both ways
- **Line Numbers** — Gutter alongside the editor
- **GFM Support** — Tables, task lists, strikethrough, autolinks
- **Syntax Highlighting** — 180+ languages via highlight.js
- **LaTeX Math** — Inline (`$...$`) and block (`$$...$$`) math with KaTeX
- **Mermaid Diagrams** — Flowcharts, sequence diagrams, and more
- **Quick Look** — Preview `.md` files in Finder with spacebar
- **File Watching** — Auto-refreshes when the file changes on disk
- **Dark Mode** — Follows system appearance

## Screenshots

### Editor + Preview

![Split-pane editor with live preview](docs/assets/images/editor.png)

### Quick Look

![Quick Look preview in Finder](docs/assets/images/demo.png)

## Install

### Homebrew

```bash
brew install hulryung/tap/markdown-prism
```

### Manual

Download the latest `MarkdownPrism-x.x.x.dmg` from [Releases](../../releases), open it, and drag **Markdown Prism** to Applications.

The app is signed and notarized with Apple Developer ID.

### Troubleshooting: Homebrew Install/Upgrade Failure

If `brew install` or `brew upgrade` fails with:

```
Error: It seems the App source '.../Markdown Prism.app' is not there.
```

This is a name mismatch issue between the cask definition and the DMG. To fix:

```bash
# 1. Remove the broken state
brew uninstall --cask markdown-prism --force

# 2. Re-fetch the latest cask definition
brew tap hulryung/tap --force

# 3. Reinstall
brew install --cask hulryung/tap/markdown-prism
```

If the issue persists, install manually from the [Releases](../../releases) page.

## Build from Source

Requires macOS 14+ and Xcode 15+.

```bash
# Install xcodegen (if needed)
brew install xcodegen

# Generate Xcode project and build
xcodegen generate
xcodebuild -scheme MarkdownPrism -configuration Release build
```

For SPM-only build (no Quick Look extension):

```bash
swift build
swift run
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| App Shell | Swift / SwiftUI |
| Preview Rendering | WKWebView + HTML/JS |
| Markdown Parser | markdown-it |
| Code Highlighting | highlight.js |
| Math Rendering | KaTeX |
| Diagrams | Mermaid.js |
| Quick Look | QLPreviewingController + WKWebView |

## License

MIT
