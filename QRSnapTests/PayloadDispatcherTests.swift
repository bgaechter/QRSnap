#if !STANDALONE_TESTS
import XCTest
#endif
#if STANDALONE_TESTS
import Foundation
#elseif SWIFT_PACKAGE
@testable import QRSnapCore
#else
@testable import QRSnap
#endif
import os

@MainActor private final class DispatchLauncherSpy: PayloadLaunching {
    static let defaultHandler = HandlerMetadata(name: "Synthetic handler", applicationURL: URL(fileURLWithPath: "/Applications/Synthetic.app"))
    var handlerValue: HandlerMetadata? = defaultHandler
    var lookups: [URL] = []
    var opens: [URL] = []
    var onLookup: ((URL) -> HandlerMetadata?)?
    var onOpen: ((URL) async -> LaunchResult)?
    var result: LaunchResult = .handoffSucceeded
    var continuation: CheckedContinuation<LaunchResult, Never>?

    func handler(for url: URL) -> HandlerMetadata? {
        lookups.append(url)
        if let onLookup { return onLookup(url) }
        return handlerValue
    }

    func open(_ url: URL) async -> LaunchResult {
        opens.append(url)
        if let onOpen { return await onOpen(url) }
        return result
    }

    func suspendOpening() {
        onOpen = { _ in await withCheckedContinuation { self.continuation = $0 } }
    }
}

/// The synchronous Sendable storage protocol is exercised without filesystem work.
/// The lock protects the recorded data and the cancellation switch without an
/// unchecked Sendable annotation or a main-actor assumption inside createDocument.
private struct DispatchStoreSpy: TextDocumentStoring {
    struct State {
        var texts: [String] = []
        var shouldFail = false
        var invalidateOnWrite = false
        var isCurrent = true
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    let documentURL = URL(fileURLWithPath: "/synthetic/00000000-0000-0000-0000-000000000001.txt")
    var texts: [String] { state.withLock { $0.texts } }
    var isCurrent: Bool { state.withLock { $0.isCurrent } }

    func createDocument(text: String) throws -> URL {
        try state.withLock { value in
            value.texts.append(text)
            if value.invalidateOnWrite { value.isCurrent = false }
            if value.shouldFail { throw ScanFailure.fileWriteFailed }
        }
        return documentURL
    }
}

@MainActor final class PayloadDispatcherTests: XCTestCase {
    func testWebPreparationHasNoSideEffectsAndDispatchOpensOnce() async throws {
        let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
        let original = " \nhttps://example.com/a%2Fb?q=x%20y\t "
        let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
        XCTAssertEqual(prepared.original, original)
        XCTAssertTrue(launcher.lookups.isEmpty)
        XCTAssertTrue(launcher.opens.isEmpty)
        XCTAssertTrue(store.texts.isEmpty)
        let outcome = await dispatcher.dispatch(prepared, isCurrent: { true })
        XCTAssertEqual(outcome, .handoffSucceeded)
        XCTAssertEqual(launcher.opens.map(\.absoluteString), ["https://example.com/a%2Fb?q=x%20y"])
        let duplicate = await dispatcher.dispatch(prepared, isCurrent: { true })
        let alternative = await dispatcher.dispatch(prepared, action: .openAsText, isCurrent: { true })
        XCTAssertEqual(duplicate, .alreadyDispatched)
        XCTAssertEqual(alternative, .alreadyDispatched)
        XCTAssertEqual(launcher.opens.count, 1)
        XCTAssertTrue(store.texts.isEmpty)
    }

    func testRegisteredSchemesRequireExplicitConfirmation() async throws {
        for original in ["mailto:qr@example.com", "tel:+123456789", "qrsnap-test://example/action"] {
            let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
            let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
            let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
            XCTAssertEqual(prepared.route, .confirmedExternalURI(URL(string: original)!, DispatchLauncherSpy.defaultHandler))
            let automatic = await dispatcher.dispatch(prepared, isCurrent: { true })
            XCTAssertEqual(automatic, .confirmationRequired(DispatchLauncherSpy.defaultHandler))
            XCTAssertTrue(launcher.opens.isEmpty)
            XCTAssertTrue(store.texts.isEmpty)
            let confirmed = await dispatcher.dispatch(prepared, action: .openExternal, isCurrent: { true })
            XCTAssertEqual(confirmed, .handoffSucceeded)
            let duplicate = await dispatcher.dispatch(prepared, action: .openExternal, isCurrent: { true })
            XCTAssertEqual(duplicate, .alreadyDispatched)
            XCTAssertEqual(launcher.opens.map(\.absoluteString), [original])
            XCTAssertEqual(launcher.lookups.count, 2)
        }
    }

    func testChangedHandlerRequiresNewConfirmationAndMissingHandlerRetainsText() async throws {
        let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
        let original = " \nqrsnap-test://example/action\t"
        let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
        let replacement = HandlerMetadata(name: "Replacement", applicationURL: URL(fileURLWithPath: "/Applications/Replacement.app"))
        launcher.handlerValue = replacement
        let changed = await dispatcher.dispatch(prepared, action: .openExternal, isCurrent: { true })
        XCTAssertEqual(changed, .confirmationRequired(replacement))
        XCTAssertEqual(prepared.route, .confirmedExternalURI(URL(string: "qrsnap-test://example/action")!, replacement))
        XCTAssertTrue(launcher.opens.isEmpty)
        let confirmed = await dispatcher.dispatch(prepared, action: .openExternal, isCurrent: { true })
        XCTAssertEqual(confirmed, .handoffSucceeded)
        XCTAssertEqual(launcher.opens.count, 1)

        let missing = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
        launcher.handlerValue = nil
        let failed = await dispatcher.dispatch(missing, action: .openExternal, isCurrent: { true })
        XCTAssertEqual(failed, .failure(.handlerUnavailable, retainedText: original, documentURL: nil))
        XCTAssertEqual(launcher.opens.count, 1)
    }

    func testUnknownSchemesAndMalformedURLsOpenOriginalText() async throws {
        for original in [" \nunknown:synthetic\t ", "https://example.com/%zz", "www.example.com", "WIFI:T:WPA;S:test;P:synthetic;;"] {
            let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
            launcher.handlerValue = nil
            launcher.onLookup = { $0.isFileURL ? DispatchLauncherSpy.defaultHandler : nil }
            let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
            let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
            XCTAssertEqual(prepared.route, .plainText(original))
            let outcome = await dispatcher.dispatch(prepared, isCurrent: { true })
            XCTAssertEqual(outcome, .handoffSucceeded)
            XCTAssertEqual(store.texts, [original])
            XCTAssertEqual(launcher.opens, [store.documentURL])
        }
    }

    func testBlockedSchemesOnlyOpenAsTextAfterExplicitAction() async throws {
        for original in ["file:///tmp/harmless.txt", "JAVASCRIPT:synthetic", "data:text/plain,synthetic"] {
            let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
            let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
            let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
            XCTAssertEqual(prepared.route, .blockedText(original))
            let automatic = await dispatcher.dispatch(prepared, isCurrent: { true })
            let external = await dispatcher.dispatch(prepared, action: .openExternal, isCurrent: { true })
            XCTAssertEqual(automatic, .explicitTextActionRequired)
            XCTAssertEqual(external, .actionUnavailable)
            XCTAssertTrue(launcher.lookups.isEmpty)
            XCTAssertTrue(launcher.opens.isEmpty)
            XCTAssertTrue(store.texts.isEmpty)
            let text = await dispatcher.dispatch(prepared, action: .openAsText, isCurrent: { true })
            XCTAssertEqual(text, .handoffSucceeded)
            XCTAssertEqual(store.texts, [original])
            XCTAssertEqual(launcher.opens, [store.documentURL])
        }
    }

    func testUnicodeWhitespaceAndEmptyTextArePreserved() async throws {
        for original in ["\u{FEFF}Grüezi 日本語 🐱\r\n  trailing\n", "  \n\t ", ""] {
            let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
            let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
            let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
            let outcome = await dispatcher.dispatch(prepared, isCurrent: { true })
            XCTAssertEqual(outcome, .handoffSucceeded)
            XCTAssertEqual(store.texts.map { Data($0.utf8) }, [Data(original.utf8)])
            XCTAssertEqual(launcher.opens, [store.documentURL])
        }
    }

    func testStorageAndLaunchFailuresRetainOriginalAndWrittenDocument() async throws {
        let original = "  Grüezi 日本語 🐱\r\n"
        let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
        store.state.withLock { $0.shouldFail = true }
        let write = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
        let writeFailure = await dispatcher.dispatch(write, isCurrent: { true })
        XCTAssertEqual(writeFailure, .failure(.fileWriteFailed, retainedText: original, documentURL: nil))
        XCTAssertTrue(launcher.lookups.isEmpty)
        XCTAssertTrue(launcher.opens.isEmpty)

        store.state.withLock { $0.shouldFail = false }
        launcher.result = .failure(.launchFailed)
        let open = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
        let openFailure = await dispatcher.dispatch(open, isCurrent: { true })
        XCTAssertEqual(openFailure, .failure(.launchFailed, retainedText: original, documentURL: store.documentURL))
        XCTAssertEqual(launcher.opens, [store.documentURL])
        XCTAssertEqual(store.texts, [original, original])

        let webOriginal = " \nhttps://example.com/a%2Fb\t"
        let web = try XCTUnwrap(dispatcher.prepare(webOriginal, isCurrent: { true }))
        let webFailure = await dispatcher.dispatch(web, isCurrent: { true })
        XCTAssertEqual(webFailure, .failure(.launchFailed, retainedText: webOriginal, documentURL: nil))
    }

    func testMissingWebAndTextHandlersRetainOriginalWithoutLaunching() async throws {
        for original in [" \nhttps://example.com/%2F\t", "  synthetic text\n"] {
            let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
            launcher.handlerValue = nil
            let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
            let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
            let outcome = await dispatcher.dispatch(prepared, isCurrent: { true })
            XCTAssertEqual(outcome, .failure(.handlerUnavailable, retainedText: original,
                                           documentURL: store.texts.isEmpty ? nil : store.documentURL))
            XCTAssertTrue(launcher.opens.isEmpty)
        }
    }

    func testCancellationBeforePreparationAndDispatchHasNoSideEffects() async throws {
        let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
        XCTAssertNil(dispatcher.prepare("qrsnap-test://example/action", isCurrent: { false }))
        XCTAssertTrue(launcher.lookups.isEmpty)
        for original in ["https://example.com", "synthetic text", "qrsnap-test://example/action"] {
            let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
            let outcome = await dispatcher.dispatch(prepared, action: .openAsText, isCurrent: { false })
            XCTAssertEqual(outcome, .cancelled)
        }
        XCTAssertTrue(launcher.opens.isEmpty)
        XCTAssertTrue(store.texts.isEmpty)
    }

    func testCancellationAfterStorageOrHandlerLookupPreventsLaunch() async throws {
        let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
        store.state.withLock { $0.invalidateOnWrite = true }
        let prepared = try XCTUnwrap(dispatcher.prepare("synthetic text", isCurrent: { store.isCurrent }))
        let outcome = await dispatcher.dispatch(prepared, isCurrent: { store.isCurrent })
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(store.texts, ["synthetic text"])
        XCTAssertTrue(launcher.lookups.isEmpty)
        XCTAssertTrue(launcher.opens.isEmpty)

        var current = true
        let web = try XCTUnwrap(dispatcher.prepare("https://example.com", isCurrent: { current }))
        launcher.onLookup = { _ in current = false; return DispatchLauncherSpy.defaultHandler }
        let webOutcome = await dispatcher.dispatch(web, isCurrent: { current })
        XCTAssertEqual(webOutcome, .cancelled)
        XCTAssertTrue(launcher.opens.isEmpty)
        current = true
        XCTAssertNil(dispatcher.prepare("qrsnap-test://example/action", isCurrent: { current }))
    }

    func testPendingOpenRejectsDuplicateAndLateCompletionIsCancelled() async throws {
        let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
        launcher.suspendOpening()
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
        let prepared = try XCTUnwrap(dispatcher.prepare("qrsnap-test://example/action", isCurrent: { true }))
        var current = true
        let opening = Task { await dispatcher.dispatch(prepared, action: .openExternal, isCurrent: { current }) }
        for _ in 0..<100 where launcher.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(launcher.continuation)
        let duplicate = await dispatcher.dispatch(prepared, action: .openExternal, isCurrent: { current })
        XCTAssertEqual(duplicate, .alreadyDispatched)
        current = false
        continuation.resume(returning: .handoffSucceeded)
        let outcome = await opening.value
        XCTAssertEqual(outcome, .cancelled)
        // It was already handed to the launcher; cancellation cannot retract it.
        XCTAssertEqual(launcher.opens.count, 1)
    }

    func testTaskCancellationPreventsDispatchEvenWithCurrentPredicate() async throws {
        let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
        let prepared = try XCTUnwrap(dispatcher.prepare("synthetic text", isCurrent: { true }))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await dispatcher.dispatch(prepared, isCurrent: { true })
        }
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(store.texts.isEmpty)
        XCTAssertTrue(launcher.lookups.isEmpty)
        XCTAssertTrue(launcher.opens.isEmpty)
    }

    func testUnsupportedAndForeignPreparedPayloadsNeverDispatch() async throws {
        let launcher = DispatchLauncherSpy(), store = DispatchStoreSpy()
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: store)
        for original in [nil, String(repeating: "a", count: PayloadClassifier.maximumUTF8Bytes + 1)] {
            let prepared = try XCTUnwrap(dispatcher.prepare(original, isCurrent: { true }))
            let outcome = await dispatcher.dispatch(prepared, action: .openAsText, isCurrent: { true })
            XCTAssertEqual(outcome, .unsupported(.unsupportedPayload))
        }
        let other = PayloadDispatcher(launcher: launcher, textStore: store)
        let foreign = try XCTUnwrap(other.prepare("https://example.com", isCurrent: { true }))
        let outcome = await dispatcher.dispatch(foreign, isCurrent: { true })
        XCTAssertEqual(outcome, .actionUnavailable)
        XCTAssertTrue(launcher.lookups.isEmpty)
        XCTAssertTrue(launcher.opens.isEmpty)
        XCTAssertTrue(store.texts.isEmpty)
    }
}
