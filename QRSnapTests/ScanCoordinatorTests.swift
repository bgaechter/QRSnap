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
import CoreGraphics

/// Fakes intentionally ignore cancellation, like an OS callback already in flight.
@MainActor private final class DeferredCapture: ScreenCapturing {
    private(set) var calls: [UUID] = []
    private var pending: [UUID: CheckedContinuation<CapturedFrame, Error>] = [:]
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func capture(_ selection: Selection) async throws -> CapturedFrame {
        try await withCheckedThrowingContinuation { continuation in
            calls.append(selection.sessionID)
            pending[selection.sessionID] = continuation
            waiters.removeValue(forKey: selection.sessionID)?.resume()
        }
    }

    func waitForRequest(_ token: UUID) async {
        if calls.contains(token) { return }
        await withCheckedContinuation { waiters[token] = $0 }
    }

    func succeed(_ token: UUID) {
        let provider = CGDataProvider(data: Data([255, 255, 255, 255]) as CFData)!
        let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        pending.removeValue(forKey: token)?.resume(returning: CapturedFrame(image: image))
    }

    func fail(_ token: UUID, _ error: any Error) {
        pending.removeValue(forKey: token)?.resume(throwing: error)
    }
}

private actor DeferredDecoder: QRDecoding {
    private var count = 0
    private var pending: [Int: CheckedContinuation<[DecodedItem], Error>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    var callCount: Int { count }

    func decode(_ frame: CapturedFrame) async throws -> [DecodedItem] {
        count += 1
        let call = count
        return try await withCheckedThrowingContinuation { continuation in
            pending[call] = continuation
            waiters.removeValue(forKey: call)?.resume()
        }
    }

    func waitForRequest(_ call: Int) async {
        if count >= call { return }
        await withCheckedContinuation { waiters[call] = $0 }
    }

    func succeed(_ call: Int, items: [DecodedItem]) { pending.removeValue(forKey: call)?.resume(returning: items) }
    func fail(_ call: Int, _ error: any Error) { pending.removeValue(forKey: call)?.resume(throwing: error) }
}

private actor ManualScanSleeper {
    private struct Entry {
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private var entries: [Entry] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            entries.append(Entry(duration: duration, continuation: continuation))
            let ready = waiters.filter { entries.count >= $0.0 }
            waiters.removeAll { entries.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForTimers(_ count: Int = 2) async {
        if entries.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func fire(_ duration: Duration) {
        let ready = entries.filter { $0.duration == duration }
        entries.removeAll { $0.duration == duration }
        ready.forEach { $0.continuation.resume() }
    }

    func drain() {
        let ready = entries
        entries = []
        ready.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor private final class ScanEvents {
    var values: [ScanCoordinator.Event] = []
    var observer: ((ScanCoordinator.Event) -> Void)?
    func receive(_ event: ScanCoordinator.Event) {
        values.append(event)
        observer?(event)
    }
    func finished(_ token: UUID) -> [ScanCoordinator.FinishReason] {
        values.compactMap {
            if case .finished(let id, let reason) = $0, id == token { return reason }
            return nil
        }
    }
}

@MainActor private final class ScanHarness {
    let capture: DeferredCapture
    let decoder: DeferredDecoder
    let sleeper: ManualScanSleeper
    let events: ScanEvents
    let coordinator: ScanCoordinator

    init() {
        let capture = DeferredCapture(), decoder = DeferredDecoder()
        let sleeper = ManualScanSleeper(), events = ScanEvents()
        self.capture = capture
        self.decoder = decoder
        self.sleeper = sleeper
        self.events = events
        self.coordinator = ScanCoordinator(capture: capture, decoder: decoder,
                                           sleep: { try await sleeper.sleep($0) },
                                           onEvent: { events.receive($0) })
    }

    func selection(_ token: UUID) -> Selection {
        let display = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), backingScale: 1)
        return Selection(sessionID: token, display: display, topology: [display], rect: CGRect(x: 10, y: 10, width: 100, height: 100))
    }

    func startCapture() async throws -> UUID {
        let token = try XCTUnwrap(coordinator.beginSelection())
        XCTAssertTrue(coordinator.submit(selection(token)))
        await capture.waitForRequest(token)
        await sleeper.waitForTimers()
        return token
    }

    func startDecode(call: Int = 1) async throws -> UUID {
        let token = try await startCapture()
        capture.succeed(token)
        await decoder.waitForRequest(call)
        return token
    }

    func complete(_ items: [DecodedItem]) async throws -> UUID {
        let token = try await startDecode()
        await decoder.succeed(1, items: items)
        await settle()
        return token
    }

    /// Let resumed non-cooperative callbacks run before making negative event assertions.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private struct UnknownScanError: Error {}

@MainActor final class ScanCoordinatorTests: XCTestCase {
    private let item = DecodedItem(id: 0, payload: "https://example.com/synthetic", bounds: CGRect(x: 0, y: 0, width: 1, height: 1))

    func testBusyInvocationAndSelectionIdentityAreGuarded() async throws {
        let h = ScanHarness()
        let token = try XCTUnwrap(h.coordinator.beginSelection())
        XCTAssertNil(h.coordinator.beginSelection())
        XCTAssertFalse(h.coordinator.submit(h.selection(UUID())))
        XCTAssertFalse(h.coordinator.claimOpening(sessionID: token))
        XCTAssertFalse(h.coordinator.finishOpening(sessionID: token))
        XCTAssertTrue(h.coordinator.submit(h.selection(token)))
        XCTAssertFalse(h.coordinator.submit(h.selection(token)))
        await h.capture.waitForRequest(token)
        await h.sleeper.waitForTimers()
        XCTAssertNil(h.coordinator.beginSelection())
        XCTAssertEqual(h.capture.calls, [token])
        h.coordinator.cancel(sessionID: token)
        h.capture.succeed(token)
        await h.sleeper.drain()
        await h.settle()
        XCTAssertEqual(h.events.finished(token), [.cancelled])
    }

    func testCancellationDiscardsLateCaptureAndKeepsNewSession() async throws {
        let h = ScanHarness()
        let old = try await h.startCapture()
        XCTAssertTrue(h.coordinator.cancel(sessionID: old))
        XCTAssertFalse(h.coordinator.cancel(sessionID: old))
        let fresh = try XCTUnwrap(h.coordinator.beginSelection())
        h.capture.succeed(old)
        await h.sleeper.fire(.milliseconds(300))
        await h.sleeper.fire(.seconds(5))
        await h.settle()
        XCTAssertEqual(h.coordinator.sessionID, fresh)
        XCTAssertEqual(h.coordinator.phase, .selecting)
        let decodeCalls = await h.decoder.callCount
        XCTAssertEqual(decodeCalls, 0)
        XCTAssertFalse(h.events.values.contains(.progress(old, isVisible: true)))
        XCTAssertFalse(h.coordinator.claimOpening(sessionID: old))
        XCTAssertEqual(h.events.finished(old), [.cancelled])
        h.coordinator.cancel(sessionID: fresh)
    }

    func testCancelledDecodeCannotReplaceNewSessionResults() async throws {
        let h = ScanHarness()
        let old = try await h.startDecode()
        h.coordinator.cancel(sessionID: old)
        await h.sleeper.drain()
        let fresh = try await h.startDecode(call: 2)
        let freshItems = [DecodedItem(id: 1, payload: "synthetic fresh text", bounds: .zero)]
        await h.decoder.succeed(2, items: freshItems)
        await h.settle()
        XCTAssertEqual(h.coordinator.results, freshItems)
        await h.decoder.succeed(1, items: [item])
        await h.settle()
        XCTAssertEqual(h.coordinator.sessionID, fresh)
        XCTAssertEqual(h.coordinator.results, freshItems)
        XCTAssertFalse(h.events.values.contains(.results(old, [item])))
        XCTAssertFalse(h.coordinator.claimOpening(sessionID: old))
        XCTAssertTrue(h.coordinator.claimOpening(sessionID: fresh))
        XCTAssertTrue(h.coordinator.finishOpening(sessionID: fresh))
        await h.sleeper.drain()
    }

    func testTimeoutDuringCaptureDiscardsLateCompletionAndAllowsRetry() async throws {
        let h = ScanHarness()
        let token = try await h.startCapture()
        await h.sleeper.fire(.seconds(5))
        await h.settle()
        XCTAssertNil(h.coordinator.sessionID)
        XCTAssertEqual(h.events.finished(token), [.failed(.timedOut)])
        h.capture.succeed(token)
        await h.sleeper.fire(.milliseconds(300))
        await h.settle()
        let calls = await h.decoder.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(h.coordinator.claimOpening(sessionID: token))
        let retry = try XCTUnwrap(h.coordinator.beginSelection())
        h.coordinator.cancel(sessionID: retry)
    }

    func testTimeoutDuringDecodeDiscardsLateResults() async throws {
        let h = ScanHarness()
        let token = try await h.startDecode()
        await h.sleeper.fire(.seconds(5))
        await h.settle()
        await h.decoder.succeed(1, items: [item])
        await h.sleeper.fire(.milliseconds(300))
        await h.settle()
        XCTAssertEqual(h.events.finished(token), [.failed(.timedOut)])
        XCTAssertTrue(h.coordinator.results.isEmpty)
        XCTAssertFalse(h.events.values.contains(.results(token, [item])))
        XCTAssertFalse(h.coordinator.claimOpening(sessionID: token))
    }

    func testProgressIsDelayedAndReviewingStopsDeadline() async throws {
        let h = ScanHarness()
        let token = try await h.startDecode()
        XCTAssertFalse(h.events.values.contains(.progress(token, isVisible: true)))
        await h.sleeper.fire(.milliseconds(300))
        await h.settle()
        XCTAssertTrue(h.events.values.contains(.progress(token, isVisible: true)))
        await h.decoder.succeed(1, items: [item])
        await h.settle()
        XCTAssertTrue(h.events.values.contains(.progress(token, isVisible: false)))
        XCTAssertEqual(h.coordinator.phase, .reviewing)
        await h.sleeper.fire(.seconds(5))
        await h.settle()
        XCTAssertEqual(h.coordinator.phase, .reviewing)
        XCTAssertTrue(h.events.finished(token).isEmpty)
        h.coordinator.cancel(sessionID: token)
    }

    func testNoQRAndErrorsCleanUpAndPermitAnotherScan() async throws {
        let h = ScanHarness()
        let noQR = try await h.complete([])
        XCTAssertEqual(h.events.finished(noQR), [.failed(.noQR)])
        await h.sleeper.drain()
        let captureError = try await h.startCapture()
        h.capture.fail(captureError, ScanFailure.permissionUnavailable)
        await h.settle()
        XCTAssertEqual(h.events.finished(captureError), [.failed(.permissionUnavailable)])
        await h.sleeper.drain()
        let unknownCapture = try await h.startCapture()
        h.capture.fail(unknownCapture, UnknownScanError())
        await h.settle()
        XCTAssertEqual(h.events.finished(unknownCapture), [.failed(.captureFailed)])
        await h.sleeper.drain()
        let decodeError = try await h.startDecode(call: 2)
        await h.decoder.fail(2, UnknownScanError())
        await h.settle()
        XCTAssertEqual(h.events.finished(decodeError), [.failed(.decodeFailed)])
        XCTAssertEqual(h.coordinator.phase, .idle)
        XCTAssertTrue(h.coordinator.results.isEmpty)
        await h.sleeper.drain()
    }

    func testDisplayChangeCancelsSelectionCaptureDecodeAndReview() async throws {
        for stage in 0...3 {
            let h = ScanHarness()
            let token: UUID
            switch stage {
            case 0: token = try XCTUnwrap(h.coordinator.beginSelection())
            case 1: token = try await h.startCapture()
            case 2: token = try await h.startDecode()
            default: token = try await h.complete([item])
            }
            XCTAssertTrue(h.coordinator.displayDidChange(sessionID: token))
            XCTAssertFalse(h.coordinator.displayDidChange(sessionID: token))
            if stage == 1 { h.capture.succeed(token) }
            if stage == 2 { await h.decoder.succeed(1, items: [item]) }
            await h.sleeper.drain()
            await h.settle()
            XCTAssertEqual(h.events.finished(token), [.failed(.displayChanged)])
            XCTAssertTrue(h.coordinator.results.isEmpty)
            XCTAssertFalse(h.coordinator.claimOpening(sessionID: token))
        }
    }

    func testSingleAndMultipleResultsPreserveObservationsAndOpeningIsOnceOnly() async throws {
        let unsupported = DecodedItem(id: 1, payload: nil, bounds: .zero)
        let duplicate = DecodedItem(id: 2, payload: item.payload, bounds: .zero)
        for items in [[item], [item, unsupported, duplicate]] {
            let h = ScanHarness()
            let token = try await h.complete(items)
            XCTAssertEqual(h.coordinator.results, items)
            XCTAssertEqual(h.events.values.filter { if case .results = $0 { true } else { false } }, [.results(token, items)])
            XCTAssertNil(h.coordinator.beginSelection())
            XCTAssertFalse(h.coordinator.claimOpening(sessionID: UUID()))
            XCTAssertTrue(h.coordinator.claimOpening(sessionID: token))
            XCTAssertFalse(h.coordinator.claimOpening(sessionID: token))
            XCTAssertEqual(h.coordinator.phase, .opening)
            XCTAssertFalse(h.coordinator.finishOpening(sessionID: UUID()))
            XCTAssertTrue(h.coordinator.finishOpening(sessionID: token))
            XCTAssertFalse(h.coordinator.finishOpening(sessionID: token))
            XCTAssertEqual(h.events.finished(token), [.openingFinished])
            XCTAssertTrue(h.coordinator.results.isEmpty)
            await h.sleeper.drain()
        }
        // A claimed token is not authorization to launch after a later cancellation/await.
        let cancelled = ScanHarness()
        let old = try await cancelled.complete([item])
        XCTAssertTrue(cancelled.coordinator.claimOpening(sessionID: old))
        XCTAssertTrue(cancelled.coordinator.cancel(sessionID: old))
        let fresh = try XCTUnwrap(cancelled.coordinator.beginSelection())
        XCTAssertFalse(cancelled.coordinator.finishOpening(sessionID: old))
        XCTAssertFalse(cancelled.coordinator.claimOpening(sessionID: old))
        XCTAssertEqual(cancelled.coordinator.sessionID, fresh)
        cancelled.coordinator.cancel(sessionID: fresh)
        await cancelled.sleeper.drain()
    }

    func testEventReentrancyCannotPublishCancelledResultsOrInvalidateRetry() async throws {
        for replace in [false, true] {
            let selecting = ScanHarness()
            var cancelledToken: UUID?
            var replacementToken: UUID?
            selecting.events.observer = { [weak selecting] event in
                guard let selecting, case .selecting(let token) = event else { return }
                selecting.events.observer = nil
                cancelledToken = token
                selecting.coordinator.cancel(sessionID: token)
                if replace { replacementToken = selecting.coordinator.beginSelection() }
            }
            XCTAssertNil(selecting.coordinator.beginSelection())
            let old = try XCTUnwrap(cancelledToken)
            XCTAssertEqual(selecting.events.finished(old), [.cancelled])
            XCTAssertEqual(selecting.coordinator.sessionID, replacementToken)
            if replace {
                let replacement = try XCTUnwrap(replacementToken)
                XCTAssertNotEqual(old, replacement)
                XCTAssertEqual(selecting.coordinator.phase, .selecting)
                selecting.coordinator.cancel(sessionID: replacement)
            } else {
                XCTAssertEqual(selecting.coordinator.phase, .idle)
            }
        }

        let h = ScanHarness()
        let token = try await h.startDecode()
        await h.sleeper.fire(.milliseconds(300))
        await h.settle()
        var retry: UUID?
        h.events.observer = { [weak h] event in
            guard let h, event == .progress(token, isVisible: false) else { return }
            h.coordinator.cancel(sessionID: token)
            retry = h.coordinator.beginSelection()
        }
        await h.decoder.succeed(1, items: [item])
        await h.settle()
        XCTAssertNotNil(retry)
        XCTAssertEqual(h.coordinator.sessionID, retry)
        XCTAssertEqual(h.coordinator.phase, .selecting)
        XCTAssertFalse(h.events.values.contains(.results(token, [item])))
        XCTAssertEqual(h.events.finished(token), [.cancelled])
        h.coordinator.cancel(sessionID: try XCTUnwrap(retry))
        await h.sleeper.drain()
    }
}
