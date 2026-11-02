import Foundation

/// Turns a click on a rendered task-list checkbox back into the one-character
/// edit it stands for in the Markdown source.
enum TaskListToggle {
    /// One click on a rendered checkbox, on its way from the preview to the
    /// editor.
    struct Request: Equatable {
        let line: Int
        let checked: Bool
    }

    /// Matches the task marker at the start of a list item, with the mark
    /// inside the brackets captured. Blockquoted and nested items qualify;
    /// an unordered or ordered marker is required, as it is for rendering.
    private static let marker = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:>[ \t]*)*(?:[-*+]|\d+[.)])[ \t]+\[([ xX])\][ \t]"#
    )

    /// The edit that sets the task on `line` (zero-based, as the preview
    /// reports it) to `checked`: the range of the mark between the brackets
    /// and the character to put there. Nil when that line holds no task item,
    /// which happens when the document changed under the preview.
    static func edit(in text: String, line: Int, checked: Bool) -> (range: NSRange, replacement: String)? {
        let whole = text as NSString
        var lineStart = 0
        var index = 0
        var lineRange = NSRange(location: NSNotFound, length: 0)
        while lineStart < whole.length || (lineStart == whole.length && index == line && whole.length == 0) {
            let range = whole.lineRange(for: NSRange(location: lineStart, length: 0))
            if index == line {
                lineRange = range
                break
            }
            if range.length == 0 { break }
            lineStart = range.upperBound
            index += 1
        }
        guard lineRange.location != NSNotFound,
              let match = marker.firstMatch(in: text, range: lineRange)
        else { return nil }
        return (match.range(at: 1), checked ? "x" : " ")
    }

    /// `text` with the task on `line` set to `checked`, or nil when there is
    /// no task to set.
    static func apply(to text: String, line: Int, checked: Bool) -> String? {
        guard let edit = edit(in: text, line: line, checked: checked) else { return nil }
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }
}
