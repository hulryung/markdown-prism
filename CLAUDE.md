# markdown-prism

macOS-native Markdown viewer/editor with GFM, LaTeX, and Mermaid support.

## Tech Stack
- **App**: Swift / SwiftUI (macOS 14+)
- **Preview Rendering**: WKWebView + HTML/JS
- **Markdown Parser**: markdown-it (JavaScript, in WKWebView)
- **Code Highlighting**: highlight.js
- **Math Rendering**: KaTeX
- **Diagrams**: Mermaid.js

## Architecture
Hybrid native + web rendering approach:
- SwiftUI app shell with NSViewRepresentable WKWebView
- HTML template loaded locally with bundled JS libraries
- Swift <-> JS communication via WKScriptMessageHandler / evaluateJavaScript

## Project Structure
- Sources/MarkdownPrism/App/ - App entry point
- Sources/MarkdownPrism/Views/ - SwiftUI views
- Sources/MarkdownPrism/Models/ - Data models
- Sources/MarkdownPrism/Resources/ - preview.html + preview-quicklook.html shells,
  js/preview.js (shared rendering logic), css/, vendored vendor/
- Sources/QuickLookExtension/ - Quick Look .appex
- Tests/ - Unit and integration tests

## Build & Run
swift build          # app target only; SwiftPM cannot build the .appex
swift test
xcodegen generate    # after adding/removing files, before any xcodebuild
xcodebuild -scheme MarkdownPrism -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

project.yml is the source of truth for target settings and the version.
Info.plist files are generated from it — never hand-edit them.

## Status
All four planned phases (viewer, editor, Quick Look, polish) shipped; the app is
distributed via the hulryung/tap Homebrew cask. See PROGRESS.md for the current
architecture and the list of open items.

## Conventions
- Commit format: `Area: short imperative summary`
- Swift: 4-space indent, PascalCase types, camelCase vars
- Files: descriptive names matching their primary type
