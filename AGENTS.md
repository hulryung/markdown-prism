# Repository Guidelines

## Project Structure & Module Organization
`markdown-prism` is a macOS-native Markdown viewer focused on GFM, LaTeX, and Mermaid rendering.

Current top-level docs:
- `README.md`: product goal and scope.
- `AGENTS.md`: contributor workflow and standards.

When adding implementation, keep this structure:
- `App/`: macOS app entry, window lifecycle, and UI shell.
- `Core/`: Markdown parsing/rendering pipeline and feature modules.
- `Resources/`: bundled assets and sample markdown fixtures.
- `Tests/`: unit/integration tests mirroring `Core/` modules.

## Build, Test, and Development Commands
Use native macOS tooling and keep commands reproducible from terminal.

Recommended commands (once project files exist):
- `swift build`: compile core modules with SwiftPM.
- `swift test`: run automated tests.
- `xcodebuild -scheme MarkdownPrism -destination 'platform=macOS' build`: CI-friendly macOS build.
- `xcodebuild test -scheme MarkdownPrism -destination 'platform=macOS'`: run test suite via Xcode tooling.

## Coding Style & Naming Conventions
Use Swift conventions and keep rendering behavior explicit.
- Follow Swift API Design Guidelines.
- Use 4-space indentation in Swift files.
- `UpperCamelCase` for types/protocols, `lowerCamelCase` for properties/functions.
- Name feature files by responsibility (example: `MermaidRenderer.swift`, `GFMTableParser.swift`).
- Keep UI code separate from parsing/rendering logic.

## Testing Guidelines
Use `XCTest` for all automated checks.
- Place tests in `Tests/` with one test target per major module.
- Name files as `<ModuleName>Tests.swift` and methods as `test_<behavior>_<expectedResult>()`.
- Include fixture-based tests for GFM tables/task lists, LaTeX blocks/inline math, Mermaid code fences, and malformed input fallback.
- Add regression tests for every renderer bug fix.

## Commit & Pull Request Guidelines
History currently uses concise colon-style messages. Keep that pattern:
- `Area: imperative summary` (example: `Renderer: add Mermaid code block fallback`).

For pull requests:
- Explain what changed and why, with linked issue/task IDs.
- Include screenshots or short screen recordings for UI/rendering changes.
- Provide sample markdown input and expected output when touching parser/renderer behavior.
- Call out any new build steps, dependencies, or config changes.
