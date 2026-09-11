import XCTest
@testable import MarkdownPrism

@MainActor
final class DocumentOpenerTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/notes/Start.md")
    private let target = URL(fileURLWithPath: "/notes/Next.md")

    private final class Grant: FolderGranting {
        var isGranted = false
        var acceptsRequest = true
        var activated: [URL] = []
        var requested: [URL] = []
        var purpose: FolderAccess.Purpose?

        func activateGrant(containing fileURL: URL) -> Bool {
            activated.append(fileURL)
            return isGranted
        }

        func requestGrant(containing fileURL: URL, purpose: FolderAccess.Purpose) -> Bool {
            requested.append(fileURL)
            self.purpose = purpose
            isGranted = acceptsRequest
            return isGranted
        }
    }

    func test_savedFolderGrant_isActivatedBeforeOpening() {
        let grant = Grant()
        grant.isGranted = true
        var opens = 0
        let opener = DocumentOpener(access: grant, openDocument: { url, done in
            XCTAssertEqual(url, self.target)
            XCTAssertEqual(grant.activated, [self.target])
            opens += 1
            done(nil)
        }, presentFailure: { _, _, _ in XCTFail("a readable file needs no prompt") })

        opener.open(target, linkedFrom: source)

        XCTAssertEqual(opens, 1)
        XCTAssertTrue(grant.requested.isEmpty)
    }

    func test_readableFileWithoutFolderGrant_opensWithoutAsking() {
        let grant = Grant()
        let opener = DocumentOpener(access: grant, openDocument: { _, done in
            done(nil)
        }, presentFailure: { _, _, _ in XCTFail("already-readable files need no prompt") })

        opener.open(target)

        XCTAssertEqual(grant.activated, [target])
        XCTAssertTrue(grant.requested.isEmpty)
    }

    func test_permissionFailure_offersAccessThenRetriesTheSameDocument() throws {
        let grant = Grant()
        var opened: [URL] = []
        var recover: (() -> Void)?
        let retried = expectation(description: "document retried")
        let opener = DocumentOpener(access: grant, openDocument: { url, done in
            opened.append(url)
            done(grant.isGranted ? nil : CocoaError(.fileReadNoPermission))
            if grant.isGranted { retried.fulfill() }
        }, presentFailure: { url, _, recovery in
            XCTAssertEqual(url, self.target)
            recover = recovery
        })

        opener.open(target, linkedFrom: source)

        XCTAssertEqual(opened, [target])
        XCTAssertTrue(grant.requested.isEmpty, "only the explicit recovery action asks for a folder")
        try XCTUnwrap(recover)()
        wait(for: [retried], timeout: 1)
        XCTAssertEqual(opened, [target, target])
        XCTAssertEqual(grant.requested, [target])
        guard case .linkedDocument(let original) = grant.purpose else {
            return XCTFail("a link should ask for document access, not Git history")
        }
        XCTAssertEqual(original, source)
    }

    func test_permissionRecovery_waitsUntilTheOriginalOpenHasCompleted() {
        let grant = Grant()
        let retried = expectation(description: "retried after the original completion returned")
        var completingOriginalOpen = false
        let opener = DocumentOpener(access: grant, openDocument: { _, done in
            if grant.isGranted {
                XCTAssertFalse(completingOriginalOpen, "NSDocumentController still holds the failed open until its completion returns")
                done(nil)
                retried.fulfill()
            } else {
                completingOriginalOpen = true
                done(CocoaError(.fileReadNoPermission))
                completingOriginalOpen = false
            }
        }, presentFailure: { _, _, recovery in
            // NSAlert.runModal and the folder picker run inside the original
            // completion, so choosing Grant Access returns here synchronously.
            recovery?()
        })

        opener.open(target, linkedFrom: source)

        wait(for: [retried], timeout: 1)
    }

    func test_cancelledFolderPicker_doesNotRetryOrRepeatThePrompt() throws {
        let grant = Grant()
        grant.acceptsRequest = false
        var opens = 0
        var prompts = 0
        var recover: (() -> Void)?
        let opener = DocumentOpener(access: grant, openDocument: { _, done in
            opens += 1
            done(CocoaError(.fileReadNoPermission))
        }, presentFailure: { _, _, recovery in
            prompts += 1
            recover = recovery
        })

        opener.open(target, linkedFrom: source)
        try XCTUnwrap(recover)()

        XCTAssertEqual(opens, 1)
        XCTAssertEqual(prompts, 1)
        XCTAssertEqual(grant.requested, [target])
    }

    func test_permissionFailureAfterGrant_reportsErrorWithoutAnotherGrantLoop() throws {
        let grant = Grant()
        var opens = 0
        var recoveries: [(() -> Void)?] = []
        let failedAgain = expectation(description: "retry failure reported")
        let opener = DocumentOpener(access: grant, openDocument: { _, done in
            opens += 1
            done(CocoaError(.fileReadNoPermission))
        }, presentFailure: { _, _, recovery in
            recoveries.append(recovery)
            if recoveries.count == 2 { failedAgain.fulfill() }
        })

        opener.open(target)
        try XCTUnwrap(recoveries.first!)()
        wait(for: [failedAgain], timeout: 1)

        XCTAssertEqual(opens, 2)
        XCTAssertEqual(grant.requested, [target])
        XCTAssertEqual(recoveries.count, 2)
        XCTAssertNil(recoveries.last!)
    }

    func test_nonPermissionFailures_keepTheirErrorAndDoNotOfferFolderAccess() {
        for code in [CocoaError.fileNoSuchFile, .fileReadNoSuchFile, .fileReadCorruptFile] {
            let grant = Grant()
            var presented = false
            let opener = DocumentOpener(access: grant, openDocument: { _, done in
                done(CocoaError(code))
            }, presentFailure: { _, error, recovery in
                presented = true
                XCTAssertEqual((error as NSError).code, code.rawValue)
                XCTAssertNil(recovery)
            })

            opener.open(target)

            XCTAssertTrue(presented)
            XCTAssertTrue(grant.requested.isEmpty)
        }
    }

    func test_posixPermissionFailuresIncludingUnderlyingErrors_offerRecovery() {
        let errors: [Error] = [
            NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
            NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [
                NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
            ])
        ]
        for error in errors {
            var offered = false
            let opener = DocumentOpener(access: Grant(), openDocument: { _, done in
                done(error)
            }, presentFailure: { _, _, recovery in offered = recovery != nil })

            opener.open(target)

            XCTAssertTrue(offered)
        }
    }
}
