import AppKit

/// Keeps document windows and recents with NSDocumentController while offering
/// a recoverable folder grant when a link crosses the sandbox boundary.
@MainActor
final class DocumentOpener {
    static let shared = DocumentOpener()

    typealias OpenDocument = (URL, @escaping (Error?) -> Void) -> Void
    typealias PresentFailure = (URL, Error, (() -> Void)?) -> Void

    private let access: FolderGranting
    private let openDocument: OpenDocument
    private let presentFailure: PresentFailure

    init(
        access: FolderGranting? = nil,
        openDocument: OpenDocument? = nil,
        presentFailure: PresentFailure? = nil
    ) {
        self.access = access ?? FolderAccess.shared
        self.openDocument = openDocument ?? { url, completion in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                completion(error)
            }
        }
        self.presentFailure = presentFailure ?? Self.showFailure
    }

    func open(_ url: URL, linkedFrom source: URL? = nil) {
        open(url, linkedFrom: source, mayRequestAccess: true)
    }

    private func open(_ url: URL, linkedFrom source: URL?, mayRequestAccess: Bool) {
        // A grant made for either Git or another link must also work after the
        // next launch, before NSDocumentController tries to read the file.
        access.activateGrant(containing: url)
        openDocument(url) { error in
            guard let error else { return }
            var recovery: (() -> Void)?
            if mayRequestAccess, Self.isPermissionFailure(error) {
                recovery = {
                    guard self.access.requestGrant(containing: url, purpose: .linkedDocument(source: source)) else {
                        return
                    }
                    // NSDocumentController keeps the failed open in flight
                    // until this completion returns, including our modal panels.
                    // Retrying inside it merely returns the same cached error.
                    DispatchQueue.main.async {
                        // A filesystem error can survive the grant; report it
                        // once rather than asking for the same folder forever.
                        self.open(url, linkedFrom: source, mayRequestAccess: false)
                    }
                }
            }
            self.presentFailure(url, error, recovery)
        }
    }

    private static func isPermissionFailure(_ error: Error) -> Bool {
        var current = error as NSError
        var visited: Set<ObjectIdentifier> = []
        while visited.insert(ObjectIdentifier(current)).inserted {
            if current.domain == NSCocoaErrorDomain, current.code == NSFileReadNoPermissionError {
                return true
            }
            if current.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EPERM)].contains(current.code) {
                return true
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }

    private static func showFailure(_ url: URL, error: Error, recovery: (() -> Void)?) {
        let alert = NSAlert()
        alert.messageText = "Could not open \u{201C}\(url.lastPathComponent)\u{201D}"
        alert.alertStyle = .warning
        if let recovery {
            alert.informativeText = """
                Grant access to the folder containing this document to open it and follow other Markdown links in that folder. You only need to choose the folder once.
                """
            alert.addButton(withTitle: "Grant Access\u{2026}")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { recovery() }
        } else {
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
