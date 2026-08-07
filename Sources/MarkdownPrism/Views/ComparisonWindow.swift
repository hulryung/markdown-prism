import AppKit
import SwiftUI

/// A comparison handed over from outside, shown in a window of its own.
///
/// Deliberately not a document window. Both sides come from `git difftool`,
/// which extracts them to temporary files and deletes them the moment the tool
/// exits — so there is nothing to edit, autosave, add to Open Recent, or restore
/// on the next launch, and a document window would try to do all four.
@MainActor
enum ComparisonWindow {
    /// Held because an `NSWindowController` owns its window and nothing else
    /// here owns the controller.
    private static var controllers: [NSWindowController] = []

    /// Whether a comparison has reached the screen yet. Until it has, the app
    /// having no windows means it is still starting, not that it is finished.
    private(set) static var hasShown = false

    static func show(_ comparison: DiffLaunch.Comparison) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = comparison.name
        window.subtitle = "Comparing with Git"
        // The files behind it will not exist next launch.
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: ComparisonView(comparison: comparison))
        window.center()

        let controller = NSWindowController(window: window)
        controllers.append(controller)
        controller.showWindow(nil)
        hasShown = true
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The contents of a comparison window: the same bar and the same rendered diff
/// the document windows show, without the editor.
struct ComparisonView: View {
    let comparison: DiffLaunch.Comparison

    @ObservedObject private var settings = AppSettings.shared
    @AppStorage("zoomScale") private var zoomScale = ZoomState.defaultScale
    @AppStorage("useFullWidth") private var useFullWidth = false
    @State private var scrollSync = ScrollSyncBus()
    @State private var changeRevision = 0
    @State private var changeCount = 0
    @State private var currentChange = 0

    var body: some View {
        VStack(spacing: 0) {
            DiffBarView(
                baseline: .supplied,
                state: .ready(DiffSession.Comparison(
                    baseline: comparison.baseline,
                    current: comparison.current,
                    stats: DiffStats.between(comparison.baseline, comparison.current),
                    headSummary: comparison.name
                )),
                changeCount: changeCount,
                currentChange: currentChange,
                onNextChange: { changeRevision += 1 },
                onPreviousChange: { changeRevision -= 1 },
                onGrantAccess: {},
                onDismiss: { NSApp.keyWindow?.performClose(nil) }
            )

            PreviewView(
                markdown: comparison.current,
                baseline: comparison.baseline,
                zoomScale: zoomScale,
                searchText: "",
                searchRevision: 0,
                isRegex: false,
                useFullWidth: useFullWidth,
                fontStack: settings.previewFontStack,
                fontSize: settings.previewFontSize,
                scrollSync: scrollSync,
                changeRevision: changeRevision,
                onChangesCounted: { count, current in
                    changeCount = count
                    currentChange = current
                }
            )
        }
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            // There is no editor here for the preview to follow.
            scrollSync.isEnabled = false
        }
    }
}
