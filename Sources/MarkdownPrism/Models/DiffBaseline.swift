import Foundation

/// What the preview compares the document against when showing changes.
///
/// The three comparisons mirror the ones `git diff` offers: everything since the
/// last commit, only what has been staged, and only what has not.
enum DiffBaseline: String, CaseIterable, Identifiable {
    /// Not comparing — the preview renders the document as usual.
    case off
    /// The last commit against the editor's text, staged or not.
    case lastCommit
    /// The last commit against the index, as in `git diff --cached`.
    case staged
    /// The index against the editor's text, as in a plain `git diff`.
    case unstaged
    /// A comparison handed over from outside, with both versions supplied —
    /// `git difftool`, which extracts them itself. Not offered in the menus,
    /// because it is not something the reader can choose.
    case supplied

    var id: String { rawValue }

    var isShowingChanges: Bool { self != .off }

    /// The stored version a comparison starts from.
    var oldRevision: GitRepository.Revision? {
        switch self {
        case .off, .supplied: return nil
        case .lastCommit, .staged: return .head
        case .unstaged: return .index
        }
    }

    /// The stored version a comparison ends at, or nil when it ends at the text
    /// in the editor — which is what makes unsaved edits show up as changes.
    var newRevision: GitRepository.Revision? {
        switch self {
        case .staged: return .index
        case .off, .lastCommit, .unstaged, .supplied: return nil
        }
    }

    /// Menu wording.
    var label: String {
        switch self {
        case .off: return "Don't Show Changes"
        case .lastCommit: return "Since Last Commit"
        case .staged: return "Staged Changes"
        case .unstaged: return "Unstaged Changes"
        case .supplied: return "Supplied Comparison"
        }
    }

    /// What the bar above the preview says is being compared.
    var summary: String {
        switch self {
        case .off: return ""
        case .lastCommit: return "Changes since the last commit"
        case .staged: return "Staged changes"
        case .unstaged: return "Unstaged changes"
        case .supplied: return "Comparing two versions"
        }
    }

    /// The baselines offered in menus, in the order they are shown. `.supplied`
    /// is absent on purpose: it arrives with the launch, not from a choice.
    static var selectable: [DiffBaseline] { [.lastCommit, .staged, .unstaged] }

    static var menuOptions: [DiffBaseline] { [.off] + selectable }
}
