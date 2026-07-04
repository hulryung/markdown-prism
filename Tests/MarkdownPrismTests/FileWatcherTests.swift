import XCTest
@testable import MarkdownPrism

final class FileWatcherTests: XCTestCase {
    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
    }

    private func waitForWatcherToArm() {
        let armed = expectation(description: "watcher armed")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            armed.fulfill()
        }
        wait(for: [armed], timeout: 1.0)
    }

    func testWritingToWatchedFileFiresOnChange() throws {
        let url = makeTempURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let expectation = expectation(description: "onChange fired")
        expectation.assertForOverFulfill = false

        let watcher = FileWatcher(url: url) {
            expectation.fulfill()
        }
        watcher.start()
        waitForWatcherToArm()
        defer { watcher.stop() }

        try "updated".write(to: url, atomically: false, encoding: .utf8)

        wait(for: [expectation], timeout: 2.0)
    }

    func testStartOnNonexistentPathDoesNotCrashOrFire() {
        let url = makeTempURL()

        let expectation = expectation(description: "onChange should not fire")
        expectation.isInverted = true

        let watcher = FileWatcher(url: url) {
            expectation.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }

        wait(for: [expectation], timeout: 0.5)
    }

    func testStopPreventsFurtherNotifications() throws {
        let url = makeTempURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let expectation = expectation(description: "onChange should not fire after stop")
        expectation.isInverted = true

        let watcher = FileWatcher(url: url) {
            expectation.fulfill()
        }
        watcher.start()
        watcher.stop()

        try "updated".write(to: url, atomically: false, encoding: .utf8)

        wait(for: [expectation], timeout: 0.5)
    }

    func testDoubleStartThenStopDoesNotCrash() throws {
        let url = makeTempURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let watcher = FileWatcher(url: url) {}
        watcher.start()
        watcher.start()
        watcher.stop()

        let doneExpectation = expectation(description: "queue drained")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            doneExpectation.fulfill()
        }
        wait(for: [doneExpectation], timeout: 2.0)
    }

    func testDeletingWatchedFileFiresOnChange() throws {
        let url = makeTempURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "onChange fired on delete")
        expectation.assertForOverFulfill = false

        let watcher = FileWatcher(url: url) {
            expectation.fulfill()
        }
        watcher.start()
        waitForWatcherToArm()
        defer { watcher.stop() }

        try FileManager.default.removeItem(at: url)

        wait(for: [expectation], timeout: 2.0)
    }

    func testAtomicReplaceRearmsAndFiresOnSubsequentWrite() throws {
        let url = makeTempURL()
        try "initial".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let firstChange = expectation(description: "first onChange")
        firstChange.assertForOverFulfill = false
        let secondChange = expectation(description: "second onChange after rearm")
        secondChange.assertForOverFulfill = false

        var firedCount = 0
        let watcher = FileWatcher(url: url) {
            firedCount += 1
            if firedCount == 1 {
                firstChange.fulfill()
            } else if firedCount >= 2 {
                secondChange.fulfill()
            }
        }
        watcher.start()
        waitForWatcherToArm()
        defer { watcher.stop() }

        try "replaced once".write(to: url, atomically: true, encoding: .utf8)

        wait(for: [firstChange], timeout: 2.0)

        let laterExpectation = expectation(description: "settle after rearm")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            laterExpectation.fulfill()
        }
        wait(for: [laterExpectation], timeout: 2.0)

        try "replaced twice".write(to: url, atomically: true, encoding: .utf8)

        wait(for: [secondChange], timeout: 2.0)
    }
}
