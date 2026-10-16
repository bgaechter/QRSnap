#if !STANDALONE_TESTS
import XCTest
#endif
import Foundation
import CoreGraphics
import os
#if SWIFT_PACKAGE
@testable import QRSnapCore
#elseif !STANDALONE_TESTS
@testable import QRSnap
#endif

/// These boundaries never capture a screen, write a document, or open an app.
/// Deferred completions deliberately ignore task cancellation, like OS callbacks.
@MainActor private final class WorkflowCapture: ScreenCapturing {
    var calls: [UUID] = []
    private var pending: [UUID: CheckedContinuation<CapturedFrame, Error>] = [:]
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    func capture(_ selection: Selection) async throws -> CapturedFrame {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(selection.sessionID)
            pending[selection.sessionID] = continuation
            waiters.removeValue(forKey: selection.sessionID)?.resume()
        }
    }
    func wait(_ token: UUID) async {
        if calls.contains(token) { return }
        await withCheckedContinuation { waiters[token] = $0 }
    }
    func complete(_ token: UUID, failure: ScanFailure? = nil) {
        guard let continuation = pending.removeValue(forKey: token) else { return }
        if let failure { continuation.resume(throwing: failure); return }
        let provider = CGDataProvider(data: Data([255, 255, 255, 255]) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        continuation.resume(returning: CapturedFrame(image: image))
    }
}

private actor WorkflowDecoder: QRDecoding {
    private var count = 0
    private var pending: [Int: CheckedContinuation<[DecodedItem], Error>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    func decode(_ frame: CapturedFrame) async throws -> [DecodedItem] {
        count += 1
        let call = count
        return try await withCheckedThrowingContinuation { continuation in
            pending[call] = continuation
            waiters.removeValue(forKey: call)?.resume()
        }
    }
    func wait(_ call: Int) async {
        if count >= call { return }
        await withCheckedContinuation { waiters[call] = $0 }
    }
    func complete(_ call: Int, items: [DecodedItem]) { pending.removeValue(forKey: call)?.resume(returning: items) }
}

private actor WorkflowSleeper {
    private var count = 0
    private var pending: [(Duration, CheckedContinuation<Void, Error>)] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func sleep(_ duration: Duration) async throws {
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

private struct WorkflowStore: TextDocumentStoring {
    struct State {
        var texts: [String] = []
        var fail = false
        var onWrite: (@MainActor @Sendable () -> Void)?
    }
    let state = OSAllocatedUnfairLock(initialState: State())
    let url = URL(fileURLWithPath: "/synthetic/workflow-document.txt")
    var texts: [String] { state.withLock { $0.texts } }
    func createDocument(text: String) throws -> URL {
        let (hook, fail) = state.withLock { value in
            value.texts.append(text)
            return (value.onWrite, value.fail)
        }
        // PayloadDispatcher invokes its synchronous store from the main actor.
        // This hook deliberately reenters that actor to test cancellation at this boundary.
        if let hook { MainActor.assumeIsolated { hook() } }
        if fail { throw ScanFailure.fileWriteFailed }
        return url
    }
}

@MainActor private final class WorkflowLaunches {
    static let handler = HandlerMetadata(name: "Synthetic", applicationURL: URL(fileURLWithPath: "/Applications/Synthetic.app"))
    var handlerValue: HandlerMetadata? = handler
    var onLookup: ((URL) -> HandlerMetadata?)?
    var onOpen: ((URL) -> Void)?
    var result: LaunchResult = .handoffSucceeded
    var deferred = false
    var lookups: [URL] = []
    var opens: [URL] = []
    var predicates: [@MainActor () -> Bool] = []
    private var pending: [Int: CheckedContinuation<LaunchResult, Never>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    func open(_ url: URL) async -> LaunchResult {
        opens.append(url)
        let call = opens.count
        onOpen?(url)
        if !deferred { waiters.removeValue(forKey: call)?.resume(); return result }
        return await withCheckedContinuation { continuation in
            pending[call] = continuation
            waiters.removeValue(forKey: call)?.resume()
        }
    }
    func wait(_ call: Int) async {
        if opens.count >= call { return }
        await withCheckedContinuation { waiters[call] = $0 }
    }
    func complete(_ call: Int, result: LaunchResult = .handoffSucceeded) { pending.removeValue(forKey: call)?.resume(returning: result) }
}

@MainActor private final class WorkflowLauncher: PayloadLaunching {
    let calls: WorkflowLaunches
    let isCurrent: @MainActor () -> Bool
    init(calls: WorkflowLaunches, isCurrent: @escaping @MainActor () -> Bool) {
        self.calls = calls
        self.isCurrent = isCurrent
        calls.predicates.append(isCurrent)
    }
    func handler(for url: URL) -> HandlerMetadata? {
        guard isCurrent() else { return nil }
        calls.lookups.append(url)
        if let onLookup = calls.onLookup { return onLookup(url) }
        return calls.handlerValue
    }
    func open(_ url: URL) async -> LaunchResult {
        guard isCurrent() else { return .failure(.launchFailed) }
        return await calls.open(url)
    }
}

@MainActor private final class WorkflowEvents {
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
        if let event = values.first(where: predicate) { return event }
        return await withCheckedContinuation { waiters.append((predicate, $0)) }
    }
    func finish(_ token: UUID) async -> ScanWorkflow.Outcome {
        let event = await wait { if case .finished(let id, _) = $0 { return id == token }; return false }
        guard case .finished(_, let outcome) = event else { preconditionFailure() }
        return outcome
    }
    func request(_ token: UUID, excluding old: UUID? = nil) async -> ScanWorkflow.ActionRequest {
        let event = await wait {
            if case .actionRequired(let request) = $0 { return request.sessionID == token && request.id != old }
            return false
        }
        guard case .actionRequired(let request) = event else { preconditionFailure() }
        return request
    }
    func finishes(_ token: UUID) -> [ScanWorkflow.Outcome] {
        values.compactMap { if case .finished(let id, let outcome) = $0, id == token { return outcome }; return nil }
    }
}

@MainActor private final class WorkflowHarness {
    let capture = WorkflowCapture()
    let decoder = WorkflowDecoder()
    let sleeper = WorkflowSleeper()
    let store = WorkflowStore()
    let launches = WorkflowLaunches()
    let events = WorkflowEvents()
    var workflow: ScanWorkflow!
    private var timerCalls = 0
    private var decodeCalls = 0
    init() {
        workflow = ScanWorkflow(capture: capture, decoder: decoder, textStore: store,
                                makeLauncher: { [launches] in WorkflowLauncher(calls: launches, isCurrent: $0) },
                                sleep: { [sleeper] in try await sleeper.sleep($0) },
                                onEvent: { [events] in events.receive($0) })
    }
    func selection(_ token: UUID) -> Selection {
        let display = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 1)
        return Selection(sessionID: token, display: display, topology: [display], rect: CGRect(x: 5, y: 5, width: 30, height: 30))
    }
    func startCapture() async throws -> UUID {
        let token = try XCTUnwrap(workflow.beginSelection())
        XCTAssertTrue(workflow.submit(selection(token)))
        await capture.wait(token)
        timerCalls += 2
        await sleeper.wait(timerCalls)
        return token
    }
    func startDecode() async throws -> (UUID, Int) {
        let token = try await startCapture()
        capture.complete(token)
        decodeCalls += 1
        await decoder.wait(decodeCalls)
        return (token, decodeCalls)
    }
    func decode(_ items: [DecodedItem]) async throws -> UUID {
        let (token, call) = try await startDecode()
        await decoder.complete(call, items: items)
        return token
    }
}

@MainActor final class ScanWorkflowTests: XCTestCase {
    private func item(_ payload: String?, id: Int = 0) -> DecodedItem {
        DecodedItem(id: id, payload: payload, bounds: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testSingleWebAndUnicodeTextCompleteThroughBothComponents() async throws {
        for original in [" \nhttps://example.com/a%2Fb?q=x%20y\t", " \nGrüezi · 日本語 · 🐱\nsecond line\t", ""] {
            let h = WorkflowHarness()
            h.launches.onOpen = { _ in XCTAssertEqual(h.workflow.phase, .opening) }
            let token = try await h.decode([item(original)])
            let outcome = await h.events.finish(token)
            XCTAssertEqual(outcome, .handoffSucceeded)
            XCTAssertNil(h.workflow.sessionID)
            XCTAssertEqual(h.workflow.phase, .idle)
            if original.contains("https:") {
                XCTAssertEqual(h.launches.opens.map(\.absoluteString), ["https://example.com/a%2Fb?q=x%20y"])
                XCTAssertTrue(h.store.texts.isEmpty)
            } else {
                XCTAssertEqual(h.launches.opens, [h.store.url])
                XCTAssertEqual(h.store.texts, [original])
            }
            XCTAssertEqual(h.events.finishes(token).count, 1)
            XCTAssertFalse(h.workflow.choose(sessionID: token, observationID: 0))
            await h.sleeper.drain()
        }
    }

    func testMultipleObservationsPreserveDuplicatesAndLockTheChoice() async throws {
        let h = WorkflowHarness()
        let items = [item("https://example.com/first", id: 7), item(nil, id: 8), item("https://example.com/first", id: 9)]
        let token = try await h.decode(items)
        let event = await h.events.wait { if case .choose(let id, _) = $0 { return id == token }; return false }
        XCTAssertEqual(event, .choose(token, items))
        XCTAssertTrue(h.launches.lookups.isEmpty)
        XCTAssertTrue(h.launches.opens.isEmpty)
        XCTAssertTrue(h.store.texts.isEmpty)
        XCTAssertNil(h.workflow.beginSelection())
        XCTAssertFalse(h.workflow.choose(sessionID: UUID(), observationID: 7))
        XCTAssertFalse(h.workflow.choose(sessionID: token, observationID: 123))
        XCTAssertTrue(h.workflow.choose(sessionID: token, observationID: 9))
        XCTAssertFalse(h.workflow.choose(sessionID: token, observationID: 7))
        let outcome = await h.events.finish(token)
        XCTAssertEqual(outcome, .handoffSucceeded)
        XCTAssertEqual(h.launches.opens.count, 1)
        await h.sleeper.drain()
    }

    func testHandlerChangeRequiresNewConfirmationAndRejectsOldRequest() async throws {
        let h = WorkflowHarness()
        let original = " \nqrsnap-test://example/action\t"
        let observation = item(original, id: 12)
        let token = try await h.decode([observation])
        let first = await h.events.request(token)
        XCTAssertEqual(first.observation, observation)
        XCTAssertEqual(first.kind, .confirmExternal(URL(string: "qrsnap-test://example/action")!, WorkflowLaunches.handler))
        XCTAssertEqual(h.workflow.phase, .reviewing)
        XCTAssertTrue(h.launches.opens.isEmpty)
        let replacement = HandlerMetadata(name: "Replacement", applicationURL: URL(fileURLWithPath: "/Applications/Replacement.app"))
        h.launches.handlerValue = replacement
        XCTAssertTrue(h.workflow.confirm(requestID: first.id))
        XCTAssertFalse(h.workflow.confirm(requestID: first.id))
        let second = await h.events.request(token, excluding: first.id)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(second.kind, .confirmExternal(URL(string: "qrsnap-test://example/action")!, replacement))
        XCTAssertEqual(h.workflow.phase, .reviewing)
        XCTAssertFalse(h.workflow.confirm(requestID: first.id))
        XCTAssertFalse(h.workflow.openAsText(requestID: first.id))
        XCTAssertTrue(h.launches.opens.isEmpty)
        XCTAssertTrue(h.workflow.confirm(requestID: second.id))
        let outcome = await h.events.finish(token)
        XCTAssertEqual(outcome, .handoffSucceeded)
        XCTAssertEqual(h.launches.opens.map(\.absoluteString), ["qrsnap-test://example/action"])
        XCTAssertTrue(h.store.texts.isEmpty)
        await h.sleeper.drain()
    }

    func testBlockedAndExternalRequestsOpenOriginalOnlyAsExplicitText() async throws {
        for original in ["  file:///tmp/synthetic\n", "javascript:synthetic", "data:text/plain,synthetic", " \nqrsnap-test://example/action\t"] {
            let h = WorkflowHarness()
            let token = try await h.decode([item(original)])
            let request = await h.events.request(token)
            XCTAssertTrue(h.launches.opens.isEmpty)
            XCTAssertTrue(h.store.texts.isEmpty)
            if !original.contains("qrsnap-test:") {
                XCTAssertEqual(request.kind, .openBlockedAsText)
                XCTAssertFalse(h.workflow.confirm(requestID: request.id))
            }
            XCTAssertTrue(h.workflow.openAsText(requestID: request.id))
            XCTAssertFalse(h.workflow.openAsText(requestID: request.id))
            let outcome = await h.events.finish(token)
            XCTAssertEqual(outcome, .handoffSucceeded)
            XCTAssertEqual(h.store.texts, [original])
            XCTAssertEqual(h.launches.opens, [h.store.url])
            await h.sleeper.drain()
        }
    }

    func testNoObservationAndSelectedNilPayloadHaveDistinctFailures() async throws {
        for multiple in [false, true] {
            let h = WorkflowHarness()
            let token = try await h.decode(multiple ? [item("https://example.com/unused", id: 2), item(nil, id: 3)] : [])
            if multiple {
                _ = await h.events.wait { if case .choose = $0 { return true }; return false }
                XCTAssertTrue(h.workflow.choose(sessionID: token, observationID: 3))
            }
            let outcome = await h.events.finish(token)
            XCTAssertEqual(outcome, .failed(multiple ? .unsupportedPayload : .noQR, retainedText: nil, documentURL: nil))
            XCTAssertTrue(h.launches.opens.isEmpty)
            XCTAssertTrue(h.store.texts.isEmpty)
            let fresh = try XCTUnwrap(h.workflow.beginSelection())
            XCTAssertTrue(h.workflow.cancel(sessionID: fresh))
            await h.sleeper.drain()
        }
    }

    func testFailuresRetainExactPayloadAndCreatedDocument() async throws {
        for mode in 0...3 {
            let h = WorkflowHarness()
            let original = " \nUnicode 🐱\nretained\t"
            if mode == 0 { h.store.state.withLock { $0.fail = true } }
            if mode == 1 { h.launches.handlerValue = nil }
            if mode == 2 { h.launches.result = .failure(.launchFailed) }
            let payload = mode == 3 ? "qrsnap-test://example/missing" : original
            let token = try await h.decode([item(payload)])
            if mode == 3 {
                let request = await h.events.request(token)
                h.launches.handlerValue = nil
                XCTAssertTrue(h.workflow.confirm(requestID: request.id))
            }
            let outcome = await h.events.finish(token)
            let reason: ScanFailure = mode == 0 ? .fileWriteFailed : mode == 2 ? .launchFailed : .handlerUnavailable
            XCTAssertEqual(outcome, .failed(reason, retainedText: payload, documentURL: mode == 1 || mode == 2 ? h.store.url : nil))
            XCTAssertEqual(h.launches.opens.count, mode == 2 ? 1 : 0)
            XCTAssertNil(h.workflow.sessionID)
            await h.sleeper.drain()
        }
    }

    func testUnknownSchemeUsesTextFallbackThroughWorkflow() async throws {
        let h = WorkflowHarness()
        h.launches.onLookup = { $0.isFileURL ? WorkflowLaunches.handler : nil }
        let original = " \nunknown:synthetic\t"
        let token = try await h.decode([item(original)])
        let outcome = await h.events.finish(token)
        XCTAssertEqual(outcome, .handoffSucceeded)
        XCTAssertEqual(h.store.texts, [original])
        XCTAssertEqual(h.launches.opens, [h.store.url])
        await h.sleeper.drain()
    }

    func testCancellationDuringLookupOrStoragePreventsHandoff() async throws {
        for storage in [false, true] {
            let h = WorkflowHarness()
            let (token, call) = try await h.startDecode()
            if storage {
                h.store.state.withLock { $0.onWrite = { XCTAssertTrue(h.workflow.cancel(sessionID: token)) } }
            } else {
                h.launches.onLookup = { _ in
                    XCTAssertTrue(h.workflow.cancel(sessionID: token))
                    return WorkflowLaunches.handler
                }
            }
            await h.decoder.complete(call, items: [item(storage ? "retained synthetic text" : "https://example.com/cancel")])
            let outcome = await h.events.finish(token)
            XCTAssertEqual(outcome, .cancelled)
            XCTAssertTrue(h.launches.opens.isEmpty)
            XCTAssertEqual(h.store.texts, storage ? ["retained synthetic text"] : [])
            XCTAssertTrue(h.launches.predicates.allSatisfy { !$0() })
            await h.sleeper.drain()
        }
    }

    func testCancelledCaptureAndTimedOutDecodeCannotDispatchIntoNewSession() async throws {
        for duringDecode in [false, true] {
            let h = WorkflowHarness()
            let old: UUID
            if duringDecode {
                let (token, _) = try await h.startDecode()
                old = token
                await h.sleeper.fire(.seconds(5))
            } else {
                old = try await h.startCapture()
                XCTAssertTrue(h.workflow.cancel(sessionID: old))
            }
            let outcome = await h.events.finish(old)
            XCTAssertEqual(outcome, duringDecode ? .failed(.timedOut, retainedText: nil, documentURL: nil) : .cancelled)
            if duringDecode { await h.decoder.complete(1, items: [item("https://example.com/stale")]) }
            else { h.capture.complete(old) }
            await h.sleeper.drain()
            let fresh = try await h.decode([item("https://example.com/fresh")])
            let freshOutcome = await h.events.finish(fresh)
            XCTAssertEqual(freshOutcome, .handoffSucceeded)
            XCTAssertEqual(h.launches.opens.map(\.absoluteString), ["https://example.com/fresh"])
            XCTAssertEqual(h.events.finishes(old), [outcome])
            await h.sleeper.drain()
        }
    }

    func testPendingHandoffAndLateCompletionCannotFinishReplacementSession() async throws {
        let h = WorkflowHarness()
        h.launches.deferred = true
        let old = try await h.decode([item("https://example.com/submitted")])
        await h.launches.wait(1)
        XCTAssertEqual(h.workflow.phase, .opening)
        XCTAssertNil(h.workflow.beginSelection())
        XCTAssertFalse(h.workflow.choose(sessionID: old, observationID: 0))
        XCTAssertTrue(h.workflow.cancel(sessionID: old))
        let fresh = try await h.decode([item("qrsnap-test://example/new")])
        let request = await h.events.request(fresh)
        h.launches.complete(1)
        XCTAssertTrue(h.workflow.confirm(requestID: request.id))
        await h.launches.wait(2)
        XCTAssertEqual(h.workflow.sessionID, fresh)
        XCTAssertTrue(h.events.finishes(fresh).isEmpty)
        h.launches.complete(2)
        let outcome = await h.events.finish(fresh)
        XCTAssertEqual(outcome, .handoffSucceeded)
        XCTAssertEqual(h.events.finishes(old), [.cancelled])
        XCTAssertEqual(h.launches.opens.count, 2)
        await h.sleeper.drain()
    }

    func testDisplayChangeInvalidatesConfirmationAndAllStaleActions() async throws {
        let h = WorkflowHarness()
        let token = try await h.decode([item("qrsnap-test://example/action")])
        let request = await h.events.request(token)
        XCTAssertTrue(h.workflow.displayDidChange(sessionID: token))
        let outcome = await h.events.finish(token)
        XCTAssertEqual(outcome, .failed(.displayChanged, retainedText: nil, documentURL: nil))
        let fresh = try XCTUnwrap(h.workflow.beginSelection())
        XCTAssertFalse(h.workflow.confirm(requestID: request.id))
        XCTAssertFalse(h.workflow.openAsText(requestID: request.id))
        XCTAssertFalse(h.workflow.choose(sessionID: token, observationID: 0))
        XCTAssertFalse(h.workflow.cancel(sessionID: token))
        XCTAssertEqual(h.workflow.sessionID, fresh)
        XCTAssertTrue(h.launches.opens.isEmpty)
        XCTAssertTrue(h.workflow.cancel(sessionID: fresh))
        await h.sleeper.drain()
    }

    func testReentrantChoiceConfirmationAndFinishHandlersPreserveNewSession() async throws {
        for stage in 0...2 {
            let h = WorkflowHarness()
            var replacement: UUID?
            h.events.observer = { event in
                let token: UUID
                switch event {
                case .choose(let id, _) where stage == 0: token = id
                case .actionRequired(let request) where stage == 1: token = request.sessionID
                case .finished(let id, _) where stage == 2: token = id
                default: return
                }
                h.events.observer = nil
                if stage != 2 { XCTAssertTrue(h.workflow.cancel(sessionID: token)) }
                replacement = h.workflow.beginSelection()
            }
            let items = stage == 0 ? [item("https://example.com/a", id: 1), item("https://example.com/b", id: 2)]
                : [item(stage == 1 ? "qrsnap-test://example/action" : "https://example.com/complete")]
            let old = try await h.decode(items)
            let outcome = await h.events.finish(old)
            XCTAssertEqual(outcome, stage == 2 ? .handoffSucceeded : .cancelled)
            let fresh = try XCTUnwrap(replacement)
            XCTAssertEqual(h.workflow.sessionID, fresh)
            XCTAssertEqual(h.workflow.phase, .selecting)
            XCTAssertEqual(h.launches.opens.count, stage == 2 ? 1 : 0)
            XCTAssertTrue(h.workflow.cancel(sessionID: fresh))
            await h.sleeper.drain()
        }
    }

    func testCancelledCallerCannotStrandChoiceOrStartConfirmedDispatch() async throws {
        for mode in 0...2 {
            let choosing = mode == 0
            let h = WorkflowHarness()
            let items = choosing ? [item("https://example.com/a", id: 1), item("https://example.com/b", id: 2)]
                : [item(mode == 1 ? "qrsnap-test://example/action" : "file:///tmp/synthetic")]
            let token = try await h.decode(items)
            let requestID: UUID?
            if choosing {
                _ = await h.events.wait { if case .choose = $0 { return true }; return false }
                requestID = nil
            } else {
                requestID = await h.events.request(token).id
            }
            let action = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                if let requestID {
                    return mode == 1 ? h.workflow.confirm(requestID: requestID) : h.workflow.openAsText(requestID: requestID)
                }
                return h.workflow.choose(sessionID: token, observationID: 1)
            }
            let accepted = await action.value
            XCTAssertFalse(accepted)
            let outcome = await h.events.finish(token)
            XCTAssertEqual(outcome, .cancelled)
            XCTAssertTrue(h.launches.opens.isEmpty)
            XCTAssertTrue(h.store.texts.isEmpty)
            let fresh = try XCTUnwrap(h.workflow.beginSelection())
            XCTAssertTrue(h.workflow.cancel(sessionID: fresh))
            await h.sleeper.drain()
        }
    }
}
