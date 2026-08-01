import Foundation

/// Holds a security-scoped resource open for as long as the instance lives.
///
/// The sandbox grants access to a file only for the session in which the user
/// picked it. To reopen a file from the Open Recent menu after a relaunch we
/// resolve a stored bookmark and keep the resulting access alive while the
/// document stays open — reads, the file watcher, and saves all need it.
final class SecurityScopedAccess {
    private let url: URL

    /// Fails when `url` carries no sandbox extension, which means the caller
    /// already has access (Open panel, drag & drop, Finder launch).
    init?(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        self.url = url
    }

    deinit {
        url.stopAccessingSecurityScopedResource()
    }
}
