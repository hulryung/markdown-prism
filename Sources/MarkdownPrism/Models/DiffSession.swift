import Foundation

/// A stored version of a document the preview can compare against.
///
/// `GitRepository` is the only real implementation; the protocol exists so the
/// state machine below can be tested without a repository on disk.
protocol DiffSource {
    func text(at revision: GitRepository.Revision, for fileURL: URL) throws -> String?
    func headSummary() -> String?
}

extension GitRepository: DiffSource {}

/// Owns which comparison a window is showing, and the reading behind it.
///
/// Kept out of the view so the interesting part — deciding what a pair of
/// missing, present or unreadable revisions means — can be tested directly.
@MainActor
final class DiffSession: ObservableObject {
    /// Why no comparison is on screen. Each maps to something the reader can
    /// act on, which is why "untracked" and "not a repository" are separate.
    enum Reason: Equatable {
        /// The repository folder has not been granted to this sandboxed app yet.
        case needsAccess
        case notARepository
        case gitUnavailable
        case untracked
        case failed(String)
    }

    struct Comparison: Equatable {
        /// The stored version being compared against.
        var baseline: String
        /// The version being compared *to*, when that is also a stored one
        /// rather than whatever is in the editor.
        var current: String?
        var stats: DiffStats
        var headSummary: String?
    }

    enum State: Equatable {
        case off
        case loading
        case ready(Comparison)
        case unavailable(Reason)
    }

    @Published private(set) var state: State = .off
    @Published private(set) var baseline: DiffBaseline = .off

    private let access: RepositoryGranting
    private let open: (URL) throws -> DiffSource
    /// Reads are asynchronous and the reader can switch comparisons while one is
    /// in flight, so results carry the request they answer.
    private var token = 0

    /// `access` defaults to the shared store; it is resolved here rather than in
    /// the signature because a default argument is evaluated at the call site,
    /// which is not necessarily on the main actor.
    init(
        access: RepositoryGranting? = nil,
        open: @escaping (URL) throws -> DiffSource = { try GitRepository.discover(containing: $0) }
    ) {
        self.access = access ?? RepositoryAccess.shared
        self.open = open
    }

    // MARK: - Driving

    func select(_ baseline: DiffBaseline, for fileURL: URL?, text: String) {
        self.baseline = baseline
        reload(for: fileURL, text: text)
    }

    /// Re-reads the stored side. Worth doing when the file, or the repository
    /// under it, may have moved on — not on every keystroke.
    func reload(for fileURL: URL?, text: String) {
        token += 1

        guard baseline.isShowingChanges else {
            state = .off
            return
        }
        guard let fileURL else {
            state = .unavailable(.notARepository)
            return
        }

        // Opens a repository granted earlier, and reports whether there was one.
        // The read is attempted either way: a build that is not sandboxed, or a
        // repository already within reach, needs no grant, and asking first
        // would put a panel in front of readers who never needed one.
        let isGranted = access.activateGrant(containing: fileURL)

        state = .loading
        let token = self.token
        let baseline = self.baseline
        let open = self.open

        DispatchQueue.global(qos: .userInitiated).async {
            var outcome = Self.read(open: open, baseline: baseline, fileURL: fileURL, editorText: text)

            // Inside the sandbox an ungranted repository is indistinguishable
            // from no repository — git simply cannot see it — so an unreachable
            // one is worth offering the panel for rather than declaring the file
            // unversioned.
            if outcome == .unavailable(.notARepository), !isGranted {
                outcome = .unavailable(.needsAccess)
            }

            Task { @MainActor in
                guard token == self.token else { return }
                self.state = outcome
            }
        }
    }

    /// Asks for the repository folder, then loads if it was granted.
    func requestAccess(for fileURL: URL, text: String) {
        guard access.requestGrant(containing: fileURL) else { return }
        reload(for: fileURL, text: text)
    }

    /// Recounts against text that has just been typed. The stored side has not
    /// moved, so this deliberately touches no repository.
    func updateCounts(for text: String) {
        guard case .ready(var comparison) = state, comparison.current == nil else { return }
        comparison.stats = DiffStats.between(comparison.baseline, text)
        state = .ready(comparison)
    }

    // MARK: - Reading

    // Both of these run on a background queue: reading a repository shells out
    // to git, which has no business blocking the main thread.
    private nonisolated static func read(
        open: (URL) throws -> DiffSource,
        baseline: DiffBaseline,
        fileURL: URL,
        editorText: String
    ) -> State {
        do {
            let source = try open(fileURL)
            return try comparison(
                from: source,
                baseline: baseline,
                fileURL: fileURL,
                editorText: editorText
            )
        } catch let failure as GitRepository.Failure {
            switch failure {
            case .gitUnavailable: return .unavailable(.gitUnavailable)
            case .notARepository: return .unavailable(.notARepository)
            case .commandFailed(let message): return .unavailable(.failed(message))
            }
        } catch {
            return .unavailable(.failed(error.localizedDescription))
        }
    }

    private nonisolated static func comparison(
        from source: DiffSource,
        baseline: DiffBaseline,
        fileURL: URL,
        editorText: String
    ) throws -> State {
        guard let oldRevision = baseline.oldRevision else { return .off }

        let stored = try source.text(at: oldRevision, for: fileURL)

        var current: String?
        if let newRevision = baseline.newRevision {
            guard let staged = try source.text(at: newRevision, for: fileURL) else {
                return .unavailable(.untracked)
            }
            current = staged
        }

        // Absent from every revision means git has never been told about the
        // file at all. A file that is merely new since the last commit is still
        // in the index, and compares against an empty baseline.
        if stored == nil, current == nil, try source.text(at: .index, for: fileURL) == nil {
            return .unavailable(.untracked)
        }

        let before = stored ?? ""
        return .ready(Comparison(
            baseline: before,
            current: current,
            stats: DiffStats.between(before, current ?? editorText),
            headSummary: source.headSummary()
        ))
    }
}

extension DiffSession.Reason {
    /// What the bar above the preview says went wrong.
    var message: String {
        switch self {
        case .needsAccess:
            return "Markdown Prism needs access to this file's Git repository."
        case .notARepository:
            return "No Git repository found for this file."
        case .gitUnavailable:
            return "Git is not available. Install the Xcode Command Line Tools to show changes."
        case .untracked:
            return "This file is not tracked by Git yet."
        case .failed(let message):
            return message.isEmpty ? "Could not read this file's history." : message
        }
    }
}
