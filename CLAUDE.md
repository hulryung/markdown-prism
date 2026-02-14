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
- Sources/MarkdownPrism/Resources/ - HTML, JS, CSS for preview
- Tests/ - Unit and integration tests

## Build & Run
swift build
swift run  (or open in Xcode)

## Phase Roadmap
1. Phase 1: File viewer (WKWebView + markdown-it + highlight.js + KaTeX + Mermaid)
2. Phase 2: Editor + real-time preview (split pane)
3. Phase 3: Quick Look extension (.appex)
4. Phase 4: Polish (themes, preferences, performance)

## Conventions
- Commit format: `Area: short imperative summary`
- Swift: 4-space indent, PascalCase types, camelCase vars
- Files: descriptive names matching their primary type
