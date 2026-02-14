import Foundation

final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.onChange()
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit {
        stop()
    }
}
