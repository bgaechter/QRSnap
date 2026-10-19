#if !STANDALONE_TESTS && !SWIFT_PACKAGE
import AppKit
import ImageIO
import XCTest
import os
@testable import QRSnap

/// Runs the production composition and real result controls against synthetic side
/// effects. No screen permission request, capture, native Save, or app launch occurs.
@MainActor final class ScanApplicationControllerTests: XCTestCase {
    func testStartupAndDeniedPermissionHaveNoSideEffectsAndClickCancels() async throws {
        let h = ApplicationHarness()
        XCTAssertEqual(h.permission.reads, 0)
        XCTAssertEqual(h.permission.requests, 0)
        XCTAssertTrue(h.capture.calls.isEmpty)
        h.permission.granted = false
        h.ui.onExplanation = { XCTAssertFalse(h.controller.startScan()) }
        XCTAssertFalse(h.controller.startScan())
        h.ui.onExplanation = nil
        XCTAssertEqual(h.permission.requests, 0)
        XCTAssertEqual(h.ui.explanations, 1)
        XCTAssertTrue(h.ui.selections.isEmpty)
        h.permission.granted = true
        XCTAssertTrue(h.controller.startScan())
        let token = try XCTUnwrap(h.controller.sessionID)
        XCTAssertFalse(h.controller.startScan())
        XCTAssertEqual(h.permission.reads, 2)
        XCTAssertEqual(h.ui.beforeSelections, 1)
        h.ui.selections[0].complete(.success(nil))
        await h.assertFinish(token, .cancelled)
        XCTAssertNil(h.controller.sessionID)
        XCTAssertEqual(h.ui.closed, [token])
        XCTAssertEqual(h.ui.stopped, [0])
        XCTAssertTrue(h.capture.calls.isEmpty)
        XCTAssertTrue(h.launches.urls.isEmpty)
    }

    func testSingleWebAndUnicodeUseRealWorkflowAndInjectedBoundaries() async throws {
        let h = ApplicationHarness()
        let url = "https://example.com/a%20b?x=%E9%9B%AA"
        let web = try await h.decode([item(1, url)])
        await h.assertFinish(web, .handoffSucceeded)
        XCTAssertEqual(h.launches.urls.map(\.absoluteString), [url])
        XCTAssertTrue(h.store.texts.isEmpty)
        let original = "  e\u{301} 🧭\n\t尾\r\n"
        let text = try await h.decode([item(1, original)])
        await h.assertFinish(text, .handoffSucceeded)
        XCTAssertEqual(h.store.texts.map { Array($0.utf8) }, [Array(original.utf8)])
        XCTAssertEqual(h.launches.urls, [URL(string: url)!, h.store.url])
        XCTAssertEqual(h.ui.closed, [web, text])
        XCTAssertEqual(h.ui.stopped.count, 2)
        XCTAssertNil(h.controller.resultWindowController.window)
        await h.clock.drain()
    }

    func testCommittedWebAndUnicodeFixturesThroughRealVisionComposition() async throws {
        let h = ApplicationHarness(realDecoder: QRDecoder())
        let directory = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil))
        for name in ["https.png", "unicode.png"] {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let token = try h.start()
            h.ui.selections.last?.complete(.success(h.region(token)))
            await h.capture.wait(token)
            h.capture.complete(token, image: image)
            await h.assertFinish(token, .handoffSucceeded)
            XCTAssertNil(h.ui.visibleOverlay)
        }
        XCTAssertEqual(h.launches.urls, [URL(string: "https://example.com/qr")!, h.store.url])
        XCTAssertEqual(h.store.texts.map { Array($0.utf8) }, [Array("Grüezi · 日本語 · العربية · 🐱".utf8)])
        XCTAssertEqual(h.permission.requests, 0)
        await h.clock.drain()
    }

    func testSelectionSubmittedOnceAndOverlayClosesBeforeDecoderAndResults() async throws {
        let h = ApplicationHarness()
        let token = try h.start()
        let callback = h.ui.selections[0].complete
        callback(.success(h.region(UUID())))
        XCTAssertEqual(h.controller.phase, .selecting)
        callback(.success(h.region(token)))
        callback(.success(h.region(token)))
        callback(.failure(.invalidSelection))
        await h.capture.wait(token)
        XCTAssertEqual(h.capture.calls, [token])
        XCTAssertTrue(h.ui.closed.isEmpty)
        XCTAssertTrue(h.ui.processing.isEmpty)
        h.ui.onProcessing = { visible in
            if visible { XCTAssertEqual(h.ui.visibleOverlay, token) }
            else { XCTAssertNotNil(h.controller.resultWindowController.window) }
        }
        h.capture.complete(token)
        await h.decoder.wait(1)
        XCTAssertEqual(h.ui.closed, [token])
        XCTAssertEqual(h.ui.processing, [true])
        XCTAssertEqual(h.ui.operations, ["selection-show", "processing-show", "selection-close"])
        XCTAssertTrue(h.ui.stopped.isEmpty)
        await h.decoder.complete(1, items: [item(1, "https://example.com/one"), item(2, "https://example.com/two")])
        _ = await h.events.wait { if case .choose = $0 { return true }; return false }
        XCTAssertNotNil(h.controller.resultWindowController.window)
        XCTAssertEqual(h.ui.closed, [token])
        XCTAssertEqual(h.ui.processing, [true, false])
        XCTAssertEqual(h.ui.operations.last, "processing-hide")
        h.ui.onProcessing = nil
        h.controller.cancel()
        await h.assertFinish(token, .cancelled)
        await h.clock.drain()
    }

    func testChooserAndConfirmationOpenOnlyExplicitChoiceOnce() async throws {
        let h = ApplicationHarness()
        let token = try await h.decode([item(1, "https://example.com/unselected"), item(2, "qrsnap-test:chosen")])
        _ = await h.events.wait { if case .choose = $0 { return true }; return false }
        let chosen = try h.button("result-choose-2")
        let unchosen = try h.button("result-choose-1")
        chosen.performClick(nil)
        unchosen.performClick(nil)
        let request = await h.events.request(token)
        XCTAssertTrue(h.launches.urls.isEmpty)
        let open = try h.button("result-open")
        let text = try h.button("result-open-as-text")
        open.performClick(nil)
        text.performClick(nil)
        h.controller.perform(.confirm(requestID: request.id))
        await h.assertFinish(token, .handoffSucceeded)
        XCTAssertEqual(h.launches.urls.map(\.absoluteString), ["qrsnap-test:chosen"])
        XCTAssertTrue(h.store.texts.isEmpty)
        await h.clock.drain()
    }

    func testEscapeDefersToNativeSaveSheetAndKeepsResultText() async throws {
        let h = ApplicationHarness()
        let token = try await h.decode([item(1, "file:///synthetic/read-as-text")])
        _ = await h.events.request(token)
        let result = h.controller.resultWindowController.window
        // The native observer derives these flags from modalWindow, sheetParent,
        // and attachedSheet; exercise the same policy without showing a Save panel.
        for flags in [(true, false), (false, true), (true, true)] {
            h.ui.escape(hasModalWindow: flags.0, hasSheet: flags.1)
            XCTAssertEqual(h.controller.sessionID, token)
            XCTAssertTrue(h.controller.resultWindowController.window === result)
        }
        try h.button("result-copy").performClick(nil)
        XCTAssertEqual(h.ui.copied, ["file:///synthetic/read-as-text"])
        h.ui.escape(hasModalWindow: false, hasSheet: false)
        await h.assertFinish(token, .cancelled)
        XCTAssertNil(h.controller.resultWindowController.window)
        XCTAssertTrue(h.launches.urls.isEmpty)
        await h.clock.drain()
    }

    func testFailureRetainsExactTextAndRetryRejectsOldControlsAndCallbacks() async throws {
        let h = ApplicationHarness()
        let original = " \t雪 e\u{301}\r\n"
        h.launches.result = .failure(.launchFailed)
        let old = try await h.decode([item(1, original)])
        await h.assertFinish(old, .failed(.launchFailed, retainedText: original, documentURL: h.store.url))
        try h.button("result-copy").performClick(nil)
        XCTAssertEqual(h.ui.copied.map { Array($0.utf8) }, [Array(original.utf8)])
        let retry = try h.button("result-retry")
        retry.performClick(nil)
        let fresh = try XCTUnwrap(h.controller.sessionID)
        XCTAssertNotEqual(old, fresh)
        retry.performClick(nil)
        h.controller.perform(.retry(sessionID: old))
        h.controller.perform(.cancel(sessionID: old))
        h.ui.selections[0].cancel()
        h.ui.selections[0].complete(.success(h.region(old)))
        h.ui.observers[0].changed()
        XCTAssertEqual(h.controller.sessionID, fresh)
        XCTAssertEqual(h.ui.selections.count, 2)
        XCTAssertEqual(h.ui.visibleOverlay, fresh)
        h.controller.cancel()
        await h.clock.drain()
    }

    func testEscapeAfterCaptureAndDisplayChangeDuringReviewInvalidateSession() async throws {
        let h = ApplicationHarness()
        let decoding = try h.start()
        h.ui.selections[0].complete(.success(h.region(decoding)))
        await h.capture.wait(decoding)
        h.capture.complete(decoding)
        await h.decoder.wait(1)
        XCTAssertNil(h.ui.visibleOverlay)
        h.ui.observers[0].cancel()
        await h.assertFinish(decoding, .cancelled)
        let fresh = try h.start()
        await h.decoder.complete(1, items: [item(1, "https://example.com/stale")])
        h.ui.observers[0].changed()
        XCTAssertEqual(h.controller.sessionID, fresh)
        XCTAssertTrue(h.launches.urls.isEmpty)
        h.controller.cancel()
        let reviewing = try await h.decode([item(1, "qrsnap-test:pending")])
        let request = await h.events.request(reviewing)
        let open = try h.button("result-open")
        XCTAssertNil(h.ui.visibleOverlay)
        h.ui.observers.last?.changed()
        await h.assertFinish(reviewing, .failed(.displayChanged, retainedText: nil, documentURL: nil))
        open.performClick(nil)
        h.controller.perform(.confirm(requestID: request.id))
        XCTAssertTrue(h.launches.urls.isEmpty)
        XCTAssertNil(h.controller.sessionID)
        h.controller.cancel()
        await h.clock.drain()
    }

    func testLateCaptureCompletionCannotCloseReplacementOverlay() async throws {
        let h = ApplicationHarness()
        let old = try h.start()
        h.ui.selections[0].complete(.success(h.region(old)))
        await h.capture.wait(old)
        h.controller.cancel()
        let fresh = try h.start()
        h.capture.complete(old)
        await h.capture.waitReturned(old)
        XCTAssertEqual(h.controller.sessionID, fresh)
        XCTAssertEqual(h.ui.visibleOverlay, fresh)
        XCTAssertEqual(h.ui.closed, [old])
        XCTAssertTrue(h.ui.processing.isEmpty)
        let decodeCalls = await h.decoder.calls
        XCTAssertEqual(decodeCalls, 0)
        XCTAssertTrue(h.launches.urls.isEmpty)
        h.controller.cancel()
        await h.clock.drain()
    }

    func testSelectionErrorAndCaptureErrorRecoverWithoutMisreportingNoQR() async throws {
        let h = ApplicationHarness()
        let selection = try h.start()
        h.ui.selections[0].complete(.failure(.selectionTooSmall))
        await h.assertFinish(selection, .failed(.selectionTooSmall, retainedText: nil, documentURL: nil))
        XCTAssertTrue(h.capture.calls.isEmpty)
        try h.button("result-retry").performClick(nil)
        let capture = try XCTUnwrap(h.controller.sessionID)
        h.ui.selections[1].complete(.success(h.region(capture)))
        await h.capture.wait(capture)
        h.capture.complete(capture, failure: .permissionUnavailable)
        await h.assertFinish(capture, .failed(.permissionUnavailable, retainedText: nil, documentURL: nil))
        XCTAssertEqual(h.ui.closed, [selection, capture])
        XCTAssertEqual(h.permission.requests, 0)
        XCTAssertTrue(h.launches.urls.isEmpty)
        h.controller.cancel()
        XCTAssertNil(h.controller.resultWindowController.window)
        await h.clock.drain()
    }

    func testProgressTimeoutAndLateCompletionCannotAffectRetry() async throws {
        let h = ApplicationHarness()
        let old = try h.start()
        h.ui.selections[0].complete(.success(h.region(old)))
        await h.capture.wait(old)
        await h.clock.wait(2)
        await h.clock.fire(.milliseconds(300))
        _ = await h.events.wait { if case .progress(_, true) = $0 { return true }; return false }
        XCTAssertEqual(h.ui.progress.last, true)
        XCTAssertTrue(h.ui.processing.isEmpty)
        await h.clock.fire(.seconds(5))
        await h.assertFinish(old, .failed(.timedOut, retainedText: nil, documentURL: nil))
        XCTAssertEqual(h.ui.progress.last, false)
        try h.button("result-retry").performClick(nil)
        let fresh = try XCTUnwrap(h.controller.sessionID)
        h.capture.complete(old)
        await h.capture.waitReturned(old)
        XCTAssertEqual(h.controller.sessionID, fresh)
        XCTAssertEqual(h.ui.visibleOverlay, fresh)
        XCTAssertTrue(h.launches.urls.isEmpty)
        XCTAssertTrue(h.ui.processing.isEmpty)
        h.controller.shutdown()
        XCTAssertNil(h.controller.sessionID)
        XCTAssertEqual(h.ui.stopped.count, 2)
        await h.clock.drain()
    }

    func testCancelOpeningAndLateHandoffCannotDismissNewSession() async throws {
        let h = ApplicationHarness()
        h.launches.deferred = true
        let old = try await h.decode([item(1, "https://example.com/handoff")])
        await h.launches.wait()
        XCTAssertEqual(h.controller.phase, .opening)
        h.controller.cancel()
        await h.assertFinish(old, .cancelled)
        let fresh = try h.start()
        h.launches.complete()
        await h.launches.waitReturned()
        XCTAssertEqual(h.controller.sessionID, fresh)
        XCTAssertEqual(h.ui.visibleOverlay, fresh)
        XCTAssertEqual(h.launches.urls.count, 1)
        h.controller.cancel()
        await h.clock.drain()
    }

    func testSynchronousFinishCallbackCanStartNewScanWithoutOldCleanup() async throws {
        let h = ApplicationHarness()
        let old = try h.start()
        h.events.observer = { event in
            guard case .finished(let token, _) = event, token == old else { return }
            h.events.observer = nil
            XCTAssertTrue(h.controller.startScan())
        }
        h.ui.selections[0].complete(.failure(.selectionTooSmall))
        let fresh = try XCTUnwrap(h.controller.sessionID)
        XCTAssertNotEqual(fresh, old)
        XCTAssertEqual(h.ui.visibleOverlay, fresh)
        XCTAssertEqual(h.ui.closed, [old])
        XCTAssertEqual(h.ui.stopped, [0])
        XCTAssertNil(h.controller.resultWindowController.window)
        h.controller.cancel()
    }

    func testCleanupAdapterReentrancyCannotClobberNewSession() throws {
        let h = ApplicationHarness()
        let old = try h.start()
        h.ui.onClose = {
            h.ui.onClose = nil
            XCTAssertTrue(h.controller.startScan())
        }
        h.controller.cancel()
        let fresh = try XCTUnwrap(h.controller.sessionID)
        XCTAssertNotEqual(fresh, old)
        XCTAssertEqual(h.ui.visibleOverlay, fresh)
        XCTAssertEqual(h.ui.stopped, [0])
        XCTAssertNil(h.controller.resultWindowController.window)
        h.ui.observers[0].cancel()
        XCTAssertEqual(h.controller.sessionID, fresh)
        h.controller.cancel()
    }

    func testProcessingPresentationCanCancelAndRestartBeforeSelectionCloses() async throws {
        let h = ApplicationHarness()
        let old = try h.start()
        h.ui.selections[0].complete(.success(h.region(old)))
        await h.capture.wait(old)
        h.ui.onProcessing = { visible in
            guard visible else { return }
            XCTAssertEqual(h.ui.visibleOverlay, old)
            h.controller.cancel()
            XCTAssertTrue(h.controller.startScan())
        }
        h.capture.complete(old)
        await h.capture.waitReturned(old)
        await h.assertFinish(old, .cancelled)
        let fresh = try XCTUnwrap(h.controller.sessionID)
        XCTAssertNotEqual(old, fresh)
        XCTAssertEqual(h.ui.visibleOverlay, fresh)
        XCTAssertEqual(h.ui.processing, [true, false])
        XCTAssertEqual(h.ui.closed, [old])
        XCTAssertEqual(h.ui.stopped, [0])
        let decodeCalls = await h.decoder.calls
        XCTAssertEqual(decodeCalls, 0)
        XCTAssertTrue(h.launches.urls.isEmpty)
        h.ui.onProcessing = nil
        h.controller.cancel()
        await h.clock.drain()
    }

    func testProcessingDismissalCanCancelReviewAndStartNewSession() async throws {
        let h = ApplicationHarness()
        var old: UUID?
        h.ui.onProcessing = { visible in
            guard !visible, let token = h.controller.sessionID else { return }
            XCTAssertNotNil(h.controller.resultWindowController.window)
            old = token
            h.controller.cancel()
            XCTAssertTrue(h.controller.startScan())
        }
        let completed = try await h.decode([item(1, "https://example.com/one"), item(2, "https://example.com/two")])
        await h.assertFinish(completed, .cancelled)
        XCTAssertEqual(old, completed)
        let fresh = try XCTUnwrap(h.controller.sessionID)
        XCTAssertNotEqual(fresh, completed)
        XCTAssertEqual(h.ui.visibleOverlay, fresh)
        XCTAssertEqual(h.ui.processing, [true, false])
        XCTAssertNil(h.controller.resultWindowController.window)
        XCTAssertTrue(h.launches.urls.isEmpty)
        h.ui.onProcessing = nil
        h.controller.cancel()
        await h.clock.drain()
    }

    private func item(_ id: Int, _ payload: String?) -> DecodedItem { .init(id: id, payload: payload, bounds: .zero) }
}

@MainActor private final class ApplicationHarness {
    let permission = ApplicationPermission()
    let capture = ApplicationTestCapture()
    let decoder = ApplicationTestDecoder()
    let store = ApplicationTestStore()
    let launches = ApplicationTestLaunches()
    let ui = ApplicationTestUI()
    let events = ApplicationTestEvents()
    let clock = ApplicationTestClock()
    var controller: ScanApplicationController!

    init(realDecoder: (any QRDecoding)? = nil) {
        _ = NSApplication.shared
        controller = ScanApplicationController(permission: permission, capture: capture, decoder: realDecoder ?? decoder,
            textStore: store, makeLauncher: { [launches] in ApplicationTestLauncher(launches, isCurrent: $0) },
            selection: ui.selection, sessionEvents: ui.sessionEvents, textActions: ui.textActions, presentsWindows: false,
            sleep: { [clock] in try await clock.sleep($0) },
            showPermissionExplanation: { [ui] in ui.explanations += 1; ui.onExplanation?() },
            beforeSelection: { [ui] in ui.beforeSelections += 1 },
            onProgress: { [ui] in ui.progress.append($0) },
            onProcessingUI: { [ui] in
                ui.processing.append($0)
                ui.operations.append($0 ? "processing-show" : "processing-hide")
                ui.onProcessing?($0)
            }, onEvent: { [events] in events.receive($0) })
    }

    func start() throws -> UUID {
        XCTAssertTrue(controller.startScan())
        return try XCTUnwrap(controller.sessionID)
    }
    func region(_ token: UUID) -> Selection {
        let display = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 1)
        return .init(sessionID: token, display: display, topology: [display], rect: CGRect(x: 0, y: 0, width: 20, height: 20))
    }
    func decode(_ items: [DecodedItem]) async throws -> UUID {
        let token = try start()
        ui.selections.last?.complete(.success(region(token)))
        await capture.wait(token)
        let call = await decoder.calls + 1
        capture.complete(token)
        await decoder.wait(call)
        await decoder.complete(call, items: items)
        return token
    }
    func assertFinish(_ token: UUID, _ expected: ScanWorkflow.Outcome, file: StaticString = #filePath, line: UInt = #line) async {
        let outcome = await events.finish(token)
        XCTAssertEqual(outcome, expected, file: file, line: line)
    }
    func button(_ id: String) throws -> NSButton {
        func find(_ view: NSView) -> NSButton? {
            if view.identifier?.rawValue == id { return view as? NSButton }
            return view.subviews.lazy.compactMap(find).first
        }
        return try XCTUnwrap(controller.resultWindowController.window?.contentView.flatMap(find))
    }
}

@MainActor private final class ApplicationPermission: ScreenPermissionChecking {
    var granted = true
    var reads = 0
    var requests = 0
    var isGranted: Bool { reads += 1; return granted }
    func request() -> Bool { requests += 1; return granted }
}

@MainActor private final class ApplicationTestUI {
    struct SelectionCallbacks {
        let token: UUID
        let complete: @MainActor (Result<Selection?, ScanFailure>) -> Void
        let cancel: @MainActor () -> Void
        let changed: @MainActor () -> Void
    }
    struct Observer {
        let cancel: @MainActor () -> Void
        let changed: @MainActor () -> Void
    }
    var selections: [SelectionCallbacks] = []
    var observers: [Observer] = []
    var stopped: [Int] = []
    var closed: [UUID] = []
    var visibleOverlay: UUID?
    var explanations = 0
    var beforeSelections = 0
    var progress: [Bool] = []
    var processing: [Bool] = []
    var operations: [String] = []
    var copied: [String] = []
    var onClose: (() -> Void)?
    var onExplanation: (() -> Void)?
    var onProcessing: ((Bool) -> Void)?
    func escape(hasModalWindow: Bool, hasSheet: Bool) {
        if ScanApplicationController.SessionEvents.handlesEscape(hasModalWindow: hasModalWindow, hasSheet: hasSheet) {
            observers.last?.cancel()
        }
    }
    var selection: ScanApplicationController.SelectionUI {
        .init(show: { token, completion, cancel, changed in
            self.operations.append("selection-show")
            self.visibleOverlay = token
            self.selections.append(.init(token: token, complete: completion, cancel: cancel, changed: changed))
        }, close: {
            self.operations.append("selection-close")
            if let token = self.visibleOverlay { self.closed.append(token) }
            self.visibleOverlay = nil
            self.onClose?()
        })
    }
    var sessionEvents: ScanApplicationController.SessionEvents {
        .init { cancel, changed in
            let index = self.observers.count
            self.observers.append(.init(cancel: cancel, changed: changed))
            return { self.stopped.append(index) }
        }
    }
    var textActions: ScanResultWindowController.TextActions {
        .init(copy: { self.copied.append($0); return true }, chooseSaveURL: { _, completion in completion(nil); return {} },
              write: { _, _ in XCTFail("No test should write a native file") })
    }
}

@MainActor private final class ApplicationTestCapture: ScreenCapturing {
    var calls: [UUID] = []
    private var pending: [UUID: CheckedContinuation<CapturedFrame, Error>] = [:]
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var returned: Set<UUID> = []
    private var returnWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    func capture(_ selection: Selection) async throws -> CapturedFrame {
        defer {
            returned.insert(selection.sessionID)
            returnWaiters.removeValue(forKey: selection.sessionID)?.resume()
        }
        return try await withCheckedThrowingContinuation { continuation in
            calls.append(selection.sessionID)
            pending[selection.sessionID] = continuation
            waiters.removeValue(forKey: selection.sessionID)?.resume()
        }
    }
    func wait(_ token: UUID) async {
        if calls.contains(token) { return }
        await withCheckedContinuation { waiters[token] = $0 }
    }
    func waitReturned(_ token: UUID) async {
        if returned.contains(token) { return }
        await withCheckedContinuation { returnWaiters[token] = $0 }
    }
    func complete(_ token: UUID, failure: ScanFailure? = nil, image: CGImage? = nil) {
        guard let continuation = pending.removeValue(forKey: token) else { return }
        if let failure { continuation.resume(throwing: failure); return }
        if let image { continuation.resume(returning: .init(image: image)); return }
        let provider = CGDataProvider(data: Data([255, 255, 255, 255]) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        continuation.resume(returning: .init(image: image))
    }
}

private actor ApplicationTestDecoder: QRDecoding {
    private(set) var calls = 0
    private var pending: [Int: CheckedContinuation<[DecodedItem], Error>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    func decode(_ frame: CapturedFrame) async throws -> [DecodedItem] {
        calls += 1
        let index = calls
        return try await withCheckedThrowingContinuation { continuation in
            pending[index] = continuation
            waiters.removeValue(forKey: index)?.resume()
        }
    }
    func wait(_ index: Int) async {
        if calls >= index { return }
        await withCheckedContinuation { waiters[index] = $0 }
    }
    func complete(_ index: Int, items: [DecodedItem]) { pending.removeValue(forKey: index)?.resume(returning: items) }
}

private struct ApplicationTestStore: TextDocumentStoring {
    let state = OSAllocatedUnfairLock(initialState: [String]())
    let url = URL(fileURLWithPath: "/not-written/synthetic-document.txt")
    var texts: [String] { state.withLock { $0 } }
    func createDocument(text: String) throws -> URL { state.withLock { $0.append(text) }; return url }
}

@MainActor private final class ApplicationTestLaunches {
    var urls: [URL] = []
    var result: LaunchResult = .handoffSucceeded
    var deferred = false
    private var continuation: CheckedContinuation<LaunchResult, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var returned = false
    private var returnWaiter: CheckedContinuation<Void, Never>?
    func open(_ url: URL) async -> LaunchResult {
        urls.append(url)
        guard deferred else { return result }
        defer { returned = true; returnWaiter?.resume(); returnWaiter = nil }
        return await withCheckedContinuation {
            continuation = $0
            waiter?.resume()
            waiter = nil
        }
    }
    func wait() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func complete() { continuation?.resume(returning: result); continuation = nil }
    func waitReturned() async {
        if returned { return }
        await withCheckedContinuation { returnWaiter = $0 }
    }
}

@MainActor private final class ApplicationTestLauncher: PayloadLaunching {
    let effects: ApplicationTestLaunches
    let isCurrent: @MainActor () -> Bool
    init(_ effects: ApplicationTestLaunches, isCurrent: @escaping @MainActor () -> Bool) {
        self.effects = effects; self.isCurrent = isCurrent
    }
    func handler(for url: URL) -> HandlerMetadata? {
        guard isCurrent() else { return nil }
        return .init(name: "Synthetic handler", applicationURL: URL(fileURLWithPath: "/Applications/Synthetic.app"))
    }
    func open(_ url: URL) async -> LaunchResult {
        guard isCurrent(), !Task.isCancelled else { return .failure(.launchFailed) }
        return await effects.open(url)
    }
}

@MainActor private final class ApplicationTestEvents {
    var values: [ScanWorkflow.Event] = []
    var observer: ((ScanWorkflow.Event) -> Void)?
    private var waiters: [((ScanWorkflow.Event) -> Bool, CheckedContinuation<ScanWorkflow.Event, Never>)] = []
    func receive(_ event: ScanWorkflow.Event) {
        values.append(event)
        let ready = waiters.filter { $0.0(event) }
        waiters.removeAll { $0.0(event) }
        ready.forEach { $0.1.resume(returning: event) }
        observer?(event)
    }
    func wait(_ predicate: @escaping (ScanWorkflow.Event) -> Bool) async -> ScanWorkflow.Event {
        if let value = values.first(where: predicate) { return value }
        return await withCheckedContinuation { waiters.append((predicate, $0)) }
    }
    func finish(_ token: UUID) async -> ScanWorkflow.Outcome {
        let event = await wait { if case .finished(let id, _) = $0 { return id == token }; return false }
        guard case .finished(_, let outcome) = event else { fatalError("Unexpected event") }
        return outcome
    }
    func request(_ token: UUID) async -> ScanWorkflow.ActionRequest {
        let event = await wait { if case .actionRequired(let request) = $0 { return request.sessionID == token }; return false }
        guard case .actionRequired(let request) = event else { fatalError("Unexpected event") }
        return request
    }
}

private actor ApplicationTestClock {
    private var count = 0
    private var pending: [(Duration, CheckedContinuation<Void, Error>)] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func sleep(_ duration: Duration) async throws {
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            count += 1
            pending.append((duration, continuation))
            let ready = waiters.filter { count >= $0.0 }
            waiters.removeAll { count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func wait(_ requested: Int) async {
        if count >= requested { return }
        await withCheckedContinuation { waiters.append((requested, $0)) }
    }
    func fire(_ duration: Duration) {
        let ready = pending.filter { $0.0 == duration }
        pending.removeAll { $0.0 == duration }
        ready.forEach { $0.1.resume() }
    }
    func drain() {
        let ready = pending
        pending = []
        ready.forEach { $0.1.resume(throwing: CancellationError()) }
    }
}
#endif
