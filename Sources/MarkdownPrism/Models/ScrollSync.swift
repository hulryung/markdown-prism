import Foundation

/// Decides which pane is allowed to drive the other.
///
/// Syncing both ways means each pane's programmatic scroll can echo back as a
/// scroll event from the other, so without arbitration the two chase each
/// other. The pane the user last touched owns the sync until it goes quiet.
struct ScrollSyncArbiter {
    enum Pane {
        case editor
        case preview
    }

    /// How long the owning pane keeps control after its last scroll event.
    static let lockout: TimeInterval = 0.25

    private var owner: Pane?
    private var lastEventTime: TimeInterval = -.greatestFiniteMagnitude

    mutating func shouldPropagate(from pane: Pane, at time: TimeInterval) -> Bool {
        if let owner, owner != pane, time - lastEventTime < Self.lockout {
            return false
        }
        owner = pane
        lastEventTime = time
        return true
    }
}

/// Connects the two panes without routing scroll events through SwiftUI state,
/// which would re-render both panes on every scrolled pixel.
final class ScrollSyncBus {
    var scrollPreview: ((Int) -> Void)?
    var scrollEditor: ((Int) -> Void)?
    var isEnabled = true

    private var arbiter = ScrollSyncArbiter()

    private var now: TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }

    func editorDidScroll(toLine line: Int) {
        guard isEnabled, arbiter.shouldPropagate(from: .editor, at: now) else { return }
        scrollPreview?(line)
    }

    func previewDidScroll(toLine line: Int) {
        guard isEnabled, arbiter.shouldPropagate(from: .preview, at: now) else { return }
        scrollEditor?(line)
    }
}
