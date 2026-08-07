import SwiftUI

/// The strip above the preview while it is showing changes.
///
/// It carries the two things the rendered diff itself cannot say: what is being
/// compared against, and — when nothing is being compared — why not, with the
/// one action that would fix it.
struct DiffBarView: View {
    let baseline: DiffBaseline
    let state: DiffSession.State
    let changeCount: Int
    let currentChange: Int
    let onNextChange: () -> Void
    let onPreviousChange: () -> Void
    let onGrantAccess: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plusminus.circle.fill")
                .foregroundStyle(.secondary)

            Text(baseline.summary)
                .fontWeight(.medium)

            detail

            Spacer(minLength: 8)

            navigation

            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Stop showing changes")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Stepping between changes, which is what makes a long document usable —
    /// the alternative is scrolling past everything that did not change.
    @ViewBuilder
    private var navigation: some View {
        if changeCount > 0 {
            Text(currentChange > 0 ? "\(currentChange) of \(changeCount)" : "\(changeCount) changes")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: onPreviousChange) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Previous change")

            Button(action: onNextChange) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Next change")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state {
        case .off:
            EmptyView()

        case .loading:
            Text("Reading history\u{2026}")
                .foregroundStyle(.secondary)

        case .ready(let comparison):
            if comparison.stats.isEmpty {
                Text("No changes")
                    .foregroundStyle(.secondary)
            } else {
                Text("+\(comparison.stats.additions)")
                    .foregroundStyle(.green)
                Text("\u{2212}\(comparison.stats.deletions)")
                    .foregroundStyle(.red)
            }

            // Which commit is being compared against only means something for
            // the comparisons that start at one.
            if let summary = comparison.headSummary, baseline != .unstaged {
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

        case .unavailable(let reason):
            Text(reason.message)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Also offered for "not a repository": granting a folder below the
            // repository root leaves git unable to walk up to it, and picking
            // again is the fix.
            if reason == .needsAccess || reason == .notARepository {
                Button("Choose Repository\u{2026}", action: onGrantAccess)
            }
        }
    }
}
