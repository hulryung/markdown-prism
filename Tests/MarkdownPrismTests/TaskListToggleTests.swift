import XCTest
@testable import MarkdownPrism

final class TaskListToggleTests: XCTestCase {
    private let document = """
    # Shortcuts

    - [ ] **Ctrl+Up** — Mission Control
    - [x] **Ctrl+Down** — Application windows
      - [X] nested, capital mark
    1. [ ] ordered task
    > - [ ] quoted task
    - plain item with [ ] later in the line
    - [ ]not a task: no space after the brackets
    """

    func test_checking_replacesOnlyTheSpaceBetweenTheBrackets() {
        let result = TaskListToggle.apply(to: document, line: 2, checked: true)
        XCTAssertEqual(result?.components(separatedBy: "\n")[2], "- [x] **Ctrl+Up** — Mission Control")
        XCTAssertEqual(result?.count, document.count)
    }

    func test_unchecking_handlesLowerAndUpperCaseMarks() {
        XCTAssertEqual(TaskListToggle.apply(to: document, line: 3, checked: false)?.components(separatedBy: "\n")[3],
                       "- [ ] **Ctrl+Down** — Application windows")
        XCTAssertEqual(TaskListToggle.apply(to: document, line: 4, checked: false)?.components(separatedBy: "\n")[4],
                       "  - [ ] nested, capital mark")
    }

    func test_orderedAndQuotedItems_areTasksToo() {
        XCTAssertEqual(TaskListToggle.apply(to: document, line: 5, checked: true)?.components(separatedBy: "\n")[5],
                       "1. [x] ordered task")
        XCTAssertEqual(TaskListToggle.apply(to: document, line: 6, checked: true)?.components(separatedBy: "\n")[6],
                       "> - [x] quoted task")
    }

    func test_linesWithoutATaskMarker_areLeftAlone() {
        XCTAssertNil(TaskListToggle.apply(to: document, line: 0, checked: true), "heading")
        XCTAssertNil(TaskListToggle.apply(to: document, line: 1, checked: true), "blank")
        XCTAssertNil(TaskListToggle.apply(to: document, line: 7, checked: true), "brackets mid-line")
        XCTAssertNil(TaskListToggle.apply(to: document, line: 8, checked: true), "no space after brackets")
        XCTAssertNil(TaskListToggle.apply(to: document, line: 40, checked: true), "past the end")
    }

    func test_windowsLineEndings_countLinesTheSameWay() {
        let crlf = document.replacingOccurrences(of: "\n", with: "\r\n")
        let edit = TaskListToggle.edit(in: crlf, line: 3, checked: false)
        XCTAssertEqual(edit?.replacement, " ")
        XCTAssertEqual((crlf as NSString).substring(with: edit!.range), "x")
    }

    func test_theEdit_isTheSingleMarkCharacter() {
        let edit = TaskListToggle.edit(in: document, line: 2, checked: true)
        XCTAssertEqual(edit?.range.length, 1)
        XCTAssertEqual((document as NSString).substring(with: edit!.range), " ")
    }
}
