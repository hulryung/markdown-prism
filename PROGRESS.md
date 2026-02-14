# markdown-prism Phase 1 Progress Report

> Generated: 2026-02-14
> Status: Phase 1 Complete (빌드 통과, 기능 검증 필요)
> Commit: `b0c0ddc` - "App: add Phase 1 markdown viewer with WKWebView rendering"

---

## 1. 프로젝트 개요

macOS 네이티브 마크다운 뷰어. Swift/SwiftUI 앱 셸 + WKWebView 기반 하이브리드 렌더링.

**지원 기능 목표**: GFM (테이블, 체크리스트, strikethrough), 코드 하이라이팅, LaTeX 수식, Mermaid 다이어그램

---

## 2. 현재 파일 구조

```
markdown-viewer/
├── Package.swift                              # SPM 프로젝트 (macOS 14+, swift-tools-version 5.9)
├── CLAUDE.md                                  # AI 에이전트용 프로젝트 컨텍스트
├── README.md                                  # 프로젝트 소개
├── .gitignore                                 # Swift/Xcode 제외 패턴
├── .claude/settings.json                      # Claude Code 권한 설정
└── Sources/MarkdownPrism/
    ├── App/
    │   └── MarkdownPrismApp.swift             # @main SwiftUI App (13줄)
    ├── Views/
    │   ├── ContentView.swift                  # 메인 뷰 + 파일 열기/드롭 (68줄)
    │   └── PreviewView.swift                  # WKWebView NSViewRepresentable (64줄)
    ├── Models/
    │   ├── MarkdownDocument.swift             # 파일 읽기 모델 (11줄)
    │   └── FileWatcher.swift                  # DispatchSource 파일 감시 (45줄)
    └── Resources/
        ├── preview.html                       # 렌더링 템플릿 + JS 파이프라인 (86줄)
        └── css/
            └── style.css                      # GitHub 스타일 CSS (315줄)
```

**총 코드량**: 약 696줄 (12파일)

---

## 3. 아키텍처 분석

### 3.1 렌더링 파이프라인

```
[.md 파일] → [Swift: String 읽기] → [evaluateJavaScript] → [JS: renderMarkdown()]
                                                                    │
                                              ┌─────────────────────┼──────────────────┐
                                              ▼                     ▼                  ▼
                                        [markdown-it]          [KaTeX]          [Mermaid.js]
                                         GFM 파싱            수식 렌더링        다이어그램 렌더링
                                              │
                                              ▼
                                      [highlight.js ???]
                                      코드 하이라이팅
```

### 3.2 Swift ↔ JavaScript 통신

- **Swift → JS**: `WKWebView.evaluateJavaScript("window.renderMarkdown(jsonString)")`
- **문자열 이스케이프**: `JSONEncoder`로 마크다운 텍스트를 JSON 문자열로 인코딩 (안전한 방식)
- **로딩 타이밍**: Coordinator 패턴으로 페이지 로드 완료 후 렌더링 보장

### 3.3 파일 감시

- `FileWatcher`: `DispatchSource.makeFileSystemObjectSource`로 `.write`, `.rename`, `.delete` 이벤트 감시
- 리소스 정리: `deinit`에서 `stop()` 호출, cancel handler에서 `close(fd)` 호출

---

## 4. 발견된 이슈 (리뷰 필요)

### CRITICAL - 기능 누락

#### Issue #1: highlight.js 미포함
`preview.html`에 highlight.js `<script>` 태그가 없음. markdown-it의 `highlight` 옵션도 설정되지 않아 **코드 블록 구문 하이라이팅이 작동하지 않음**.

```html
<!-- 현재: highlight.js 관련 코드 없음 -->
<!-- 필요: -->
<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/github.min.css">
<script src="https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js"></script>
```

그리고 markdown-it 초기화에 highlight 옵션 추가 필요:
```javascript
const md = window.markdownit({
    highlight: function (str, lang) {
        if (lang && hljs.getLanguage(lang)) {
            return hljs.highlight(str, { language: lang }).value;
        }
        return hljs.highlightAuto(str).value;
    }
});
```

#### Issue #2: FileWatcher 미연결
`FileWatcher.swift`가 생성되었으나 `ContentView.swift`에서 **사용되지 않음**. 파일 외부 변경 시 자동 새로고침이 작동하지 않음.

```swift
// ContentView.swift에 추가 필요:
@State private var fileWatcher: FileWatcher?

private func loadFile(_ url: URL) {
    // ... 기존 코드 ...
    fileWatcher?.stop()
    fileWatcher = FileWatcher(url: url) { [self] in
        DispatchQueue.main.async { self.loadFile(url) }
    }
    fileWatcher?.start()
}
```

#### Issue #3: Refresh 버튼 / 키보드 단축키 없음
Task #3 요구사항에 있었으나 구현되지 않음:
- Refresh 버튼 (Cmd+R)
- Open 단축키 (Cmd+O)

### MEDIUM - 개선 필요

#### Issue #4: CSS 경로 해석 문제 가능성
`preview.html`에서 `href="css/style.css"` 상대 경로 사용. WKWebView의 `loadFileURL`에서 `allowingReadAccessTo`가 `templateURL.deletingLastPathComponent()` (Resources 디렉토리)로 설정되어 있어 정상 동작해야 하나, 번들 구조에 따라 문제될 수 있음.

#### Issue #5: CDN 의존성
모든 JS 라이브러리가 CDN 로드. 오프라인 환경에서 **렌더링 불가**. Phase 1에서는 허용하되, 이후 로컬 번들링 필요.

- markdown-it v14.1.0
- markdown-it-task-lists v2.1.1
- KaTeX v0.16.11
- Mermaid v11.12.0

#### Issue #6: 다크 모드 Mermaid 테마
`mermaid.initialize({ theme: 'default' })` 고정. `prefers-color-scheme: dark`일 때 `theme: 'dark'`로 전환하는 로직 없음.

#### Issue #7: Strikethrough 미설정
markdown-it의 strikethrough는 기본 비활성. `{ breaks: false }` 설정은 있으나 strikethrough enable 옵션이 명시적으로 없음. (markdown-it v14에서는 기본 활성일 수 있으나 확인 필요)

### LOW - 향후 개선

#### Issue #8: 에러 핸들링
- `Bundle.module.url()` 실패 시 무시됨 (빈 화면)
- 파일 인코딩이 UTF-8이 아닌 경우 처리 없음
- 대용량 파일에 대한 보호 없음

#### Issue #9: 앱 메타데이터 부족
- Info.plist 없음 (UTType 선언, 파일 연결)
- 앱 아이콘 없음
- About 다이얼로그 없음
- 윈도우 최소/최대 크기 제약이 `frame(minWidth:minHeight:)`만으로 설정

#### Issue #10: SwiftUI 생명주기
- `@State`로 `FileWatcher`를 관리하면 SwiftUI 뷰 재생성 시 문제 가능
- `@StateObject` + ObservableObject 패턴이 더 적합할 수 있음

---

## 5. 코드 품질 메트릭

| 항목 | 상태 | 비고 |
|------|------|------|
| `swift build` | PASS | 경고 없이 빌드 성공 |
| 코드 구조 | GOOD | 관심사 분리 잘 됨 (App/Views/Models/Resources) |
| 네이밍 | GOOD | Swift 컨벤션 준수 (PascalCase 타입, camelCase 변수) |
| JS 인젝션 안전성 | GOOD | JSONEncoder 사용하여 XSS 방지 |
| 메모리 관리 | OK | Coordinator의 webView가 weak ref |
| 테스트 | NONE | 테스트 코드 없음 |
| 문서화 | OK | CLAUDE.md 있으나 코드 주석 최소 |

---

## 6. Phase 2 준비 사항

Phase 2 (에디터 + 실시간 프리뷰)를 시작하기 전에 해결해야 할 항목:

### 필수 (Must Fix)
1. [ ] highlight.js 추가 및 코드 하이라이팅 작동 확인
2. [ ] FileWatcher를 ContentView에 연결
3. [ ] Refresh 버튼 + Cmd+O/Cmd+R 키보드 단축키

### 권장 (Should Fix)
4. [ ] Mermaid 다크 모드 테마 전환
5. [ ] strikethrough 동작 확인
6. [ ] `Bundle.module.url()` 실패 시 fallback UI

### Phase 2 범위
7. [ ] NavigationSplitView로 전환 (에디터 | 프리뷰 split)
8. [ ] NSTextView 기반 마크다운 에디터 (구문 하이라이팅)
9. [ ] 디바운스된 실시간 프리뷰 업데이트 (300-500ms)
10. [ ] 스크롤 동기화 (에디터 ↔ 프리뷰)

---

## 7. 기술 스택 요약

| 컴포넌트 | 라이브러리 | 버전 | 로드 방식 |
|----------|-----------|------|-----------|
| 앱 프레임워크 | SwiftUI | macOS 14+ | 네이티브 |
| 웹뷰 | WKWebView (WebKit) | 시스템 | 네이티브 |
| 마크다운 파서 | markdown-it | 14.1.0 | CDN |
| 체크리스트 | markdown-it-task-lists | 2.1.1 | CDN |
| 수식 | KaTeX | 0.16.11 | CDN |
| 다이어그램 | Mermaid | 11.12.0 | CDN |
| 코드 하이라이팅 | highlight.js | **미포함** | - |

---

## 8. 실행 방법

```bash
cd /Users/dkkang/dev/markdown-viewer
swift build
swift run
```

또는 Xcode에서:
```bash
open Package.swift  # Xcode에서 프로젝트 열기
```
