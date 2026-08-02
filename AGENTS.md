# Repository Guidelines

## Project Structure & Module Organization
`markdown-prism` is a macOS-native Markdown viewer and editor focused on GFM,
LaTeX, and Mermaid rendering. It is a SwiftUI shell around a WKWebView renderer.

- `Sources/MarkdownPrism/App/`: app entry point, `AppDelegate`, menu commands.
- `Sources/MarkdownPrism/Views/`: SwiftUI views and the `NSViewRepresentable`
  wrappers for the editor and preview.
- `Sources/MarkdownPrism/Models/`: `MarkdownFileDocument` (the `FileDocument`
  behind every window), decoding and encoding, file watching, syntax
  highlighting, zoom, scroll-sync mapping.
- `Sources/MarkdownPrism/Resources/`: `preview.html` and `preview-quicklook.html`
  (two shells over the same `js/preview.js`), plus `css/` and vendored `vendor/`
  libraries. Keep the vendor tags in the two shells in sync.
- `Sources/QuickLookExtension/`: the `.appex` Quick Look provider.
- `docs/`: the project site, which shares `docs/assets/images/` with the README.
  Run new screenshots through `pngquant --quality=75-98` before committing them;
  a raw window capture is several times larger for no visible gain.
- `Tests/MarkdownPrismTests/`: XCTest targets mirroring `Models/`.
- `PROGRESS.md`: current architecture, open items, and the release process.

Keep UI code separate from parsing/rendering logic, and keep rendering logic in
`js/preview.js` rather than inline in the HTML shells. The app is document-based:
prefer letting `DocumentGroup` and `NSDocument` handle file operations instead of
reimplementing open/save/recents by hand.

## Build, Test, and Development Commands
- `swift build` / `swift test`: compile and test the app target. SwiftPM cannot
  build app extensions, so this path excludes Quick Look.
- `xcodegen generate`: regenerate `MarkdownPrism.xcodeproj` from `project.yml`.
  Required after adding or removing a source file, and before any xcodebuild.
- `xcodebuild -scheme MarkdownPrism -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`:
  full build including the Quick Look extension. This is what CI runs.

`project.yml` is the source of truth for target settings and the version; the
`Info.plist` files are generated from it and must not be hand-edited.

## Coding Style & Naming Conventions
Follow the Swift API Design Guidelines.
- 4-space indentation in Swift files.
- `UpperCamelCase` for types/protocols, `lowerCamelCase` for properties/functions.
- Name files by responsibility (example: `MarkdownHighlighter.swift`).
- Comment why, not what; match the density of the surrounding code.

## Testing Guidelines
Use `XCTest` for all automated checks.
- Place tests in `Tests/MarkdownPrismTests/`, named `<TypeName>Tests.swift` with
  methods named `test_<behavior>_<expectedResult>()`.
- Model logic (line mapping, scroll arbitration, highlighting, encoding
  detection, recent documents) is unit-testable and should stay that way — pull
  logic out of the view layer rather than leaving it untested.
- Add a regression test for every renderer or editor bug fix.
- `js/preview.js` is covered by `PreviewRendererTests`, which loads the real
  shells in a headless `WKWebView` and probes the resulting DOM. Extend it when
  you touch the renderer; it also guards the Quick Look Content-Security-Policy.

## Commit & Pull Request Guidelines
Use `Area: imperative summary` (example: `Preview: cache Mermaid renders`), with
a body explaining the problem and the fix.

For pull requests:
- Explain what changed and why, with linked issue/task IDs.
- Include screenshots or short recordings for UI/rendering changes.
- Provide sample markdown and expected output when touching the renderer.
- Call out new build steps, dependencies, or config changes.
