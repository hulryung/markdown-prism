import Foundation

/// Maps between UTF-16 offsets and zero-based line numbers for a snapshot of
/// text. Rebuilt when the document changes so scroll syncing can translate a
/// text position into the line number the preview indexes its blocks by.
struct LineIndex {
    /// UTF-16 offset where each line starts. Always contains at least line 0.
    private let lineStarts: [Int]

    init(_ text: String) {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A {
                starts.append(offset)
            }
        }
        // A trailing newline opens a line that holds no characters; keeping it
        // means offset(forLine:) can still address the end of the document.
        lineStarts = starts
    }

    var lineCount: Int {
        lineStarts.count
    }

    func line(forOffset offset: Int) -> Int {
        guard offset > 0 else { return 0 }

        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    func offset(forLine line: Int) -> Int {
        lineStarts[min(max(line, 0), lineStarts.count - 1)]
    }
}
