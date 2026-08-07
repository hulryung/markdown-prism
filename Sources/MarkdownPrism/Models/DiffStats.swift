import Foundation

/// Added and removed line counts between two versions of a document, in the
/// unit `git diff --stat` reports.
///
/// The preview shows changes as rendered prose, where "three paragraphs differ"
/// is not a number anyone recognises; counting lines gives the bar something
/// that matches what `git diff` in a terminal would have said.
struct DiffStats: Equatable {
    let additions: Int
    let deletions: Int

    static let none = DiffStats(additions: 0, deletions: 0)

    var isEmpty: Bool { additions == 0 && deletions == 0 }

    /// Beyond this many edits the exact counts stop being interesting and the
    /// remainder is reported as a wholesale replacement, which keeps a pair of
    /// entirely unrelated documents from costing quadratic time.
    private static let editLimit = 5000

    static func between(_ old: String, _ new: String) -> DiffStats {
        // One table across both sides: interning them separately would hand the
        // first line of each the same identifier and call them equal.
        var identifiers: [Substring: Int] = [:]
        var oldLines = lines(of: old, into: &identifiers)
        var newLines = lines(of: new, into: &identifiers)

        // Trimming the matching head and tail is what keeps the usual case —
        // a few edits inside a long document — nearly free.
        var prefix = 0
        while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
            prefix += 1
        }
        oldLines.removeFirst(prefix)
        newLines.removeFirst(prefix)

        var suffix = 0
        while suffix < oldLines.count, suffix < newLines.count,
              oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
            suffix += 1
        }
        oldLines.removeLast(suffix)
        newLines.removeLast(suffix)

        if oldLines.isEmpty || newLines.isEmpty {
            return DiffStats(additions: newLines.count, deletions: oldLines.count)
        }

        guard let distance = editDistance(oldLines, newLines) else {
            return DiffStats(additions: newLines.count, deletions: oldLines.count)
        }

        // An edit script of `distance` insertions and deletions that also
        // accounts for the length difference pins both counts exactly, so the
        // path itself never has to be reconstructed.
        let drift = oldLines.count - newLines.count
        return DiffStats(
            additions: (distance - drift) / 2,
            deletions: (distance + drift) / 2
        )
    }

    /// Myers' greedy forward pass, which costs O((n + m) x distance) and so
    /// stays quick exactly when the two versions are close. Nil once the edit
    /// script grows past `editLimit`.
    private static func editDistance(_ old: [Int], _ new: [Int]) -> Int? {
        let n = old.count
        let m = new.count
        let maximum = min(n + m, editLimit)
        let offset = maximum

        var furthest = [Int](repeating: 0, count: 2 * maximum + 2)

        for distance in 0...maximum {
            var k = -distance
            while k <= distance {
                var x: Int
                if k == -distance || (k != distance && furthest[offset + k - 1] < furthest[offset + k + 1]) {
                    x = furthest[offset + k + 1]
                } else {
                    x = furthest[offset + k - 1] + 1
                }
                var y = x - k

                while x < n, y < m, old[x] == new[y] {
                    x += 1
                    y += 1
                }

                furthest[offset + k] = x
                if x >= n, y >= m {
                    return distance
                }
                k += 2
            }
        }
        return nil
    }

    /// Lines interned as integers: the comparison runs over them many times, and
    /// comparing identifiers beats comparing strings.
    private static func lines(of text: String, into identifiers: inout [Substring: Int]) -> [Int] {
        guard !text.isEmpty else { return [] }

        var result: [Int] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let existing = identifiers[line] {
                result.append(existing)
            } else {
                let identifier = identifiers.count
                identifiers[line] = identifier
                result.append(identifier)
            }
        }
        // A trailing newline ends the last line rather than starting an empty
        // one, which is also how git counts.
        if result.count > 1, text.hasSuffix("\n") {
            result.removeLast()
        }
        return result
    }
}
