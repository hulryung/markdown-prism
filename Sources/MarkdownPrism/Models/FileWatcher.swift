import Foundation

final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.markdownprism.filewatcher")

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        queue.async { [weak self] in
            self?.startLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopLocked()
        }
    }

    private func startLocked() {
        stopLocked()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            self.onChange()
            if !flags.isDisjoint(with: [.rename, .delete]) {
                self.rearmAfterReplace()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    private func stopLocked() {
        source?.cancel()
        source = nil
    }

    private func rearmAfterReplace(attempt: Int = 0) {
        let delay = attempt == 0 ? 0.1 : 0.2
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let fd = open(self.url.path, O_EVTONLY)
            if fd >= 0 {
                close(fd)
                self.startLocked()
            } else if attempt < 2 {
                self.rearmAfterReplace(attempt: attempt + 1)
            }
        }
    }

    deinit {
        source?.cancel()
        source = nil
    }
}
