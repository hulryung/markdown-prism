import AppKit
import SwiftUI

/// User preferences that apply to every document window.
///
/// Backed by `UserDefaults` rather than `@AppStorage` because the values are
/// needed outside the view layer too — the syntax highlighter builds fonts from
/// them, and the preview gets them injected as CSS.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }

        /// nil means "whatever the system is doing", which is also what AppKit
        /// wants for the follow-the-system case.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    /// An empty font name means "use the system face", which keeps working when
    /// a chosen font is later uninstalled.
    static let systemFontName = ""

    static let minimumFontSize: CGFloat = 9
    static let maximumFontSize: CGFloat = 32

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        editorFontName = defaults.string(forKey: Key.editorFontName) ?? Self.systemFontName
        editorFontSize = Self.clampSize(CGFloat(defaults.double(forKey: Key.editorFontSize)), default: 14)
        previewFontName = defaults.string(forKey: Key.previewFontName) ?? Self.systemFontName
        previewFontSize = Self.clampSize(CGFloat(defaults.double(forKey: Key.previewFontSize)), default: 16)
    }

    private enum Key {
        static let appearance = "appearance"
        static let editorFontName = "editorFontName"
        static let editorFontSize = "editorFontSize"
        static let previewFontName = "previewFontName"
        static let previewFontSize = "previewFontSize"
    }

    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    @Published var editorFontName: String {
        didSet { defaults.set(editorFontName, forKey: Key.editorFontName) }
    }

    @Published var editorFontSize: CGFloat {
        didSet {
            // The equality check is load-bearing. Assigning inside didSet on a
            // @Published property runs the observer again — unlike a plain
            // stored property — so without it an out-of-range value recurses
            // until the stack gives out.
            let clamped = Self.clampSize(editorFontSize, default: 14)
            guard clamped == editorFontSize else {
                editorFontSize = clamped
                return
            }
            defaults.set(Double(editorFontSize), forKey: Key.editorFontSize)
        }
    }

    @Published var previewFontName: String {
        didSet { defaults.set(previewFontName, forKey: Key.previewFontName) }
    }

    @Published var previewFontSize: CGFloat {
        didSet {
            let clamped = Self.clampSize(previewFontSize, default: 16)
            guard clamped == previewFontSize else {
                previewFontSize = clamped
                return
            }
            defaults.set(Double(previewFontSize), forKey: Key.previewFontSize)
        }
    }

    /// Puts the chosen appearance on the application, which is what makes both
    /// the native chrome and the preview's `prefers-color-scheme` follow it.
    func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    func resetToDefaults() {
        appearance = .system
        editorFontName = Self.systemFontName
        editorFontSize = 14
        previewFontName = Self.systemFontName
        previewFontSize = 16
    }

    /// The CSS `font-family` value for the preview: a chosen face first, then
    /// the stack the page ships with, so a missing font still renders sensibly.
    var previewFontStack: String {
        let fallback = "-apple-system, BlinkMacSystemFont, \"Segoe UI\", \"Noto Sans\", Helvetica, Arial, sans-serif, \"Apple Color Emoji\""
        guard !previewFontName.isEmpty else { return fallback }
        return "\"\(previewFontName)\", \(fallback)"
    }

    /// One function, not an overload pair: CGFloat is Double on every platform
    /// this ships to, so two overloads differing only in that resolve to the
    /// same signature and call each other forever.
    private static func clampSize(_ size: CGFloat, default fallback: CGFloat) -> CGFloat {
        guard size > 0 else { return fallback }
        return min(max(size, minimumFontSize), maximumFontSize)
    }
}

extension NSFont {
    /// Families that can stand in for the editor's font: fixed-pitch only, since
    /// Markdown source relies on columns lining up.
    static func monospacedFamilyNames() -> [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
        }.sorted()
    }

    /// Every family, for the preview, where proportional faces are the point.
    static func proportionalFamilyNames() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }
}
