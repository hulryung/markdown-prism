import AppKit
import CoreServices
import UniformTypeIdentifiers

enum DefaultAppHelper {
    private static let markdownUTI = "net.daringfireball.markdown" as CFString

    static var isDefaultApp: Bool {
        guard let handler = LSCopyDefaultRoleHandlerForContentType(markdownUTI, .all)?.takeRetainedValue() else {
            return false
        }
        return (handler as String).caseInsensitiveCompare(
            Bundle.main.bundleIdentifier ?? ""
        ) == .orderedSame
    }

    static func setAsDefault() {
        if isDefaultApp {
            showAlert(
                title: "Already Default",
                message: "Markdown Prism is already the default app for Markdown files.",
                style: .informational
            )
            return
        }

        registerAsDefault(showResult: true)
    }

    static func promptIfFirstLaunch() {
        let key = "hasPromptedDefaultApp"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        guard !isDefaultApp else { return }

        let alert = NSAlert()
        alert.messageText = "Set as Default Markdown App?"
        alert.informativeText = "Would you like to use Markdown Prism as your default app for opening Markdown files (.md, .markdown, .mdown, .mkd)?"
        alert.addButton(withTitle: "Set as Default")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            registerAsDefault(showResult: false)
        }
    }

    private static func registerAsDefault(showResult: Bool) {
        let bundleID = (Bundle.main.bundleIdentifier ?? "com.markdownprism.app") as CFString

        let status = LSSetDefaultRoleHandlerForContentType(markdownUTI, .all, bundleID)

        if showResult {
            if status == noErr {
                showAlert(
                    title: "Default App Updated",
                    message: "Markdown Prism is now the default app for Markdown files (.md, .markdown, .mdown, .mkd).",
                    style: .informational
                )
            } else {
                showAlert(
                    title: "Failed to Set Default App",
                    message: "Could not set default application (error \(status)).",
                    style: .warning
                )
            }
        }
    }

    private static func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
