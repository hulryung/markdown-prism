import AppKit
import XCTest
@testable import MarkdownPrism

final class AppSettingsTests: XCTestCase {
    private let suiteName = "AppSettingsTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_defaults_followTheSystemWithSystemFaces() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.editorFontName, AppSettings.systemFontName)
        XCTAssertEqual(settings.previewFontName, AppSettings.systemFontName)
        XCTAssertEqual(settings.editorFontSize, 14)
        XCTAssertEqual(settings.previewFontSize, 16)
    }

    func test_choicesSurviveARelaunch() {
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        settings.editorFontName = "Menlo"
        settings.editorFontSize = 18
        settings.previewFontName = "Georgia"
        settings.previewFontSize = 20

        let reloaded = AppSettings(defaults: defaults)

        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.editorFontName, "Menlo")
        XCTAssertEqual(reloaded.editorFontSize, 18)
        XCTAssertEqual(reloaded.previewFontName, "Georgia")
        XCTAssertEqual(reloaded.previewFontSize, 20)
    }

    func test_fontSizesAreClampedToAReadableRange() {
        let settings = AppSettings(defaults: defaults)

        settings.editorFontSize = 2
        XCTAssertEqual(settings.editorFontSize, AppSettings.minimumFontSize)

        settings.previewFontSize = 900
        XCTAssertEqual(settings.previewFontSize, AppSettings.maximumFontSize)
    }

    func test_appearanceMapsToTheAppKitValues() {
        XCTAssertNil(AppSettings.Appearance.system.nsAppearance, "system means: leave it to macOS")
        XCTAssertEqual(AppSettings.Appearance.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppSettings.Appearance.dark.nsAppearance?.name, .darkAqua)
    }

    // MARK: - Preview font stack

    func test_previewFontStack_fallsBackToTheStylesheetStack() {
        let settings = AppSettings(defaults: defaults)

        // The stylesheet's own stack, which does quote some of its fallbacks —
        // what matters is that no chosen family is put in front of it.
        XCTAssertTrue(settings.previewFontStack.hasPrefix("-apple-system"))
        XCTAssertTrue(settings.previewFontStack.contains("sans-serif"))
    }

    func test_previewFontStack_putsTheChosenFaceFirstAndKeepsFallbacks() {
        let settings = AppSettings(defaults: defaults)
        settings.previewFontName = "Iowan Old Style"

        XCTAssertTrue(settings.previewFontStack.hasPrefix("\"Iowan Old Style\","))
        XCTAssertTrue(settings.previewFontStack.contains("sans-serif"), "a missing font still has somewhere to land")
    }

    // MARK: - Editor fonts

    func test_editorFontChoices_areFixedPitch() throws {
        let families = NSFont.monospacedFamilyNames()

        XCTAssertFalse(families.isEmpty)
        for family in families.prefix(12) {
            let font = try XCTUnwrap(NSFont(name: family, size: 12))
            XCTAssertTrue(font.isFixedPitch, "\(family) would break column alignment")
        }
    }

    func test_highlighter_usesTheChosenFamily() throws {
        let highlighter = MarkdownHighlighter(fontSize: 15, fontFamily: "Menlo")

        XCTAssertEqual(highlighter.baseFont.familyName, "Menlo")
        XCTAssertEqual(highlighter.baseFont.pointSize, 15, accuracy: 0.001)
        XCTAssertTrue(highlighter.boldFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func test_highlighter_fallsBackWhenTheFamilyIsMissing() {
        let highlighter = MarkdownHighlighter(fontSize: 13, fontFamily: "No Such Font 12345")

        // Falls back to the system monospaced face rather than failing to draw.
        XCTAssertEqual(highlighter.baseFont.pointSize, 13, accuracy: 0.001)
        XCTAssertTrue(highlighter.baseFont.isFixedPitch)
    }

    func test_highlighter_stillHighlightsAfterAFamilyChange() throws {
        let highlighter = MarkdownHighlighter(fontSize: 14)
        let storage = NSTextStorage(string: "# Heading")
        highlighter.highlight(storage)

        highlighter.fontFamily = "Menlo"
        highlighter.highlight(storage)

        let attributes = storage.attributes(at: 0, effectiveRange: nil)
        let font = try XCTUnwrap(attributes[.font] as? NSFont)
        XCTAssertEqual(font.familyName, "Menlo")
        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, .systemBlue)
    }
}
