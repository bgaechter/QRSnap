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

/// Synthetic in-memory pixels and controlled workers only; no Vision analysis,
/// screen access, text persistence, or external application handoff.
@MainActor final class DecoderCancellationTests: XCTestCase {
    func testAlreadyCancelledTaskNeverSchedulesWork() async throws {
        let queue = DecoderTestQueue(), request = DecoderTestRequest()
        let decoder = QRDecoder(schedule: { queue.append($0) }, makeRequest: { request })
        let lifetime = DecoderFrameLifetime()
        let attempt = try makeAttempt(decoder, lifetime: lifetime, alreadyCancelled: true)
        defer { attempt.task?.cancel(); queue.runAll() }
        guard await waitForCompletion(attempt) else { return }
        XCTAssertEqual(attempt.outcome, .cancelled)
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(request.snapshots.count, 0)
        XCTAssertEqual(request.cancellations, 0)
        XCTAssertEqual(lifetime.releases, 1)
    }

    func testCancelBeforeContinuationInstallationReleasesFrameAndResumesOnce() async throws {
        let lifetime = DecoderFrameLifetime()
        let job = try makeJob(lifetime: lifetime)
        job.cancel()
        job.cancel()
        XCTAssertEqual(lifetime.releases, 1)
        let installed = DecoderTestFlag()
        let attempt = DecoderTestAttempt {
            try await withCheckedThrowingContinuation { continuation in
                if job.install(continuation) { installed.set() }
            }
        }
        defer { attempt.task?.cancel(); job.cancel() }
        guard await waitForCompletion(attempt) else { return }
        XCTAssertEqual(attempt.outcome, .cancelled)
        XCTAssertFalse(installed.value)
        let factories = OSAllocatedUnfairLock(initialState: 0)
        job.run {
            factories.withLock { $0 += 1 }
            return DecoderTestRequest()
        }
        XCTAssertEqual(factories.withLock { $0 }, 0)
    }

    func testQueuedCancellationReleasesPixelsBeforeItsQueuePositionRuns() async throws {
        let queue = DecoderTestQueue(), request = DecoderTestRequest()
        let decoder = QRDecoder(schedule: { queue.append($0) }, makeRequest: { request })
        let lifetime = DecoderFrameLifetime()
        let attempt = try makeAttempt(decoder, lifetime: lifetime)
        defer { attempt.task?.cancel(); queue.runAll() }
        guard await requireEventually({ queue.count == 1 }, "Decoder did not enqueue work.") else { return }
        attempt.task?.cancel()
        guard await waitForCompletion(attempt) else { return }
        XCTAssertEqual(lifetime.releases, 1)
        XCTAssertEqual(queue.count, 1) // The queue still retains the cancelled job.
        queue.runAll()
        XCTAssertEqual(attempt.outcome, .cancelled)
        XCTAssertEqual(request.snapshots.count, 0)
        XCTAssertEqual(request.cancellations, 0)
    }

    func testCancelDuringRequestCreationReleasesFrameAndPreventsPerform() async throws {
        let queue = DecoderTestQueue(), request = DecoderTestRequest()
        let entered = DecoderTestFlag(), release = DispatchSemaphore(value: 0)
        let decoder = QRDecoder(schedule: { queue.append($0) }, makeRequest: {
            entered.set()
            _ = release.wait(timeout: .now() + 10)
            return request
        })
        let lifetime = DecoderFrameLifetime()
        let attempt = try makeAttempt(decoder, lifetime: lifetime)
        defer { release.signal(); attempt.task?.cancel(); queue.runAll() }
        guard await requireEventually({ queue.count == 1 }, "Decoder did not enqueue work.") else { return }
        let drained = try runWorker(queue)
        guard await requireEventually({ entered.value }, "Request creation did not begin.") else { return }
        attempt.task?.cancel()
        guard await waitForCompletion(attempt) else { return }
        XCTAssertEqual(lifetime.releases, 1)
        release.signal()
        guard await requireEventually({ drained.value }, "Request creation worker did not return.") else { return }
        XCTAssertEqual(attempt.outcome, .cancelled)
        XCTAssertEqual(request.snapshots.count, 0)
        XCTAssertEqual(request.cancellations, 0) // This request was never registered as active.
    }

    func testActiveCancellationReturnsBeforeWorkerAndDiscardsLateCompletion() async throws {
        for throwsLate in [false, true] {
            let queue = DecoderTestQueue(), release = DispatchSemaphore(value: 0)
            let request = DecoderTestRequest { _ in
                guard release.wait(timeout: .now() + 10) == .success else { throw DecoderTestError.workerFailed }
                if throwsLate { throw DecoderTestError.workerFailed }
                return [DecodedItem(id: 0, payload: "synthetic", bounds: .zero)]
            }
            let decoder = QRDecoder(schedule: { queue.append($0) }, makeRequest: { request })
            let lifetime = DecoderFrameLifetime()
            let attempt = try makeAttempt(decoder, lifetime: lifetime)
            defer { release.signal(); attempt.task?.cancel(); queue.runAll() }
            guard await requireEventually({ queue.count == 1 }, "Decoder did not enqueue work.") else { return }
            let drained = try runWorker(queue)
            guard await requireEventually({ request.snapshots.count == 1 }, "Request did not begin.") else { return }
            attempt.task?.cancel()
            attempt.task?.cancel()
            guard await waitForCompletion(attempt) else { return }
            XCTAssertEqual(request.cancellations, 1)
            XCTAssertFalse(drained.value)
            XCTAssertEqual(lifetime.releases, 0) // Active work can still own its pixels.
            release.signal()
            guard await requireEventually({ drained.value }, "Cancelled worker did not return.") else { return }
            XCTAssertEqual(attempt.outcome, .cancelled)
            XCTAssertEqual(lifetime.releases, 1)
        }
    }

    func testCancelledBacklogDoesNotRunRequestsAheadOfFreshDecode() async throws {
        let queue = DecoderTestQueue(), request = DecoderTestRequest { _ in
            [DecodedItem(id: 3, payload: "fresh", bounds: .zero)]
        }
        let factories = OSAllocatedUnfairLock(initialState: 0)
        let decoder = QRDecoder(schedule: { queue.append($0) }, makeRequest: {
            factories.withLock { $0 += 1 }
            return request
        })
        var attempts: [DecoderTestAttempt] = []
        defer {
            attempts.forEach { $0.task?.cancel() }
            queue.runAll()
        }
        for index in 1...8 {
            let lifetime = DecoderFrameLifetime()
            let attempt = try makeAttempt(decoder, lifetime: lifetime)
            attempts.append(attempt)
            guard await requireEventually({ queue.count == index }, "Decoder did not enqueue work.") else { return }
            attempt.task?.cancel()
            guard await waitForCompletion(attempt) else { return }
            XCTAssertEqual(lifetime.releases, 1)
        }
        let fresh = try makeAttempt(decoder, lifetime: DecoderFrameLifetime())
        defer { fresh.task?.cancel() }
        guard await requireEventually({ queue.count == 9 }, "Fresh decode was not queued.") else { return }
        queue.runAll()
        for attempt in attempts {
            XCTAssertEqual(attempt.outcome, .cancelled)
        }
        guard await waitForCompletion(fresh) else { return }
        XCTAssertEqual(fresh.outcome, .succeeded([DecodedItem(id: 3, payload: "fresh", bounds: .zero)]))
        XCTAssertEqual(factories.withLock { $0 }, 1)
        XCTAssertEqual(request.snapshots.count, 1)
    }

    func testCompletionPreservesPixelsOrientationOrderAndTypedFailure() async throws {
        let items = [
            DecodedItem(id: 0, payload: "same", bounds: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.1)),
            DecodedItem(id: 1, payload: nil, bounds: CGRect(x: 0.7, y: 0.7, width: 0.1, height: 0.1)),
            DecodedItem(id: 2, payload: "same", bounds: CGRect(x: 0.1, y: 0.7, width: 0.1, height: 0.1))
        ]
        for fails in [false, true] {
            let queue = DecoderTestQueue()
            let request = DecoderTestRequest { _ in
                if fails { throw DecoderTestError.workerFailed }
                return items
            }
            let decoder = QRDecoder(schedule: { queue.append($0) }, makeRequest: { request })
            let lifetime = DecoderFrameLifetime()
            let attempt = try makeAttempt(decoder, lifetime: lifetime)
            defer { attempt.task?.cancel(); queue.runAll() }
            guard await requireEventually({ queue.count == 1 }, "Decoder did not enqueue work.") else { return }
            queue.runAll()
            guard await waitForCompletion(attempt) else { return }
            XCTAssertEqual(attempt.outcome, fails ? .failed(.decodeFailed) : .succeeded([items[2], items[1], items[0]]))
            XCTAssertEqual(request.snapshots, [.init(width: 2, height: 1, orientation: 6)])
            XCTAssertEqual(lifetime.releases, 1)
            attempt.task?.cancel()
            XCTAssertEqual(request.cancellations, 0)
        }
    }

    func testConcurrentCancellationAndCompletionResumeOnlyOnce() async throws {
        for _ in 0..<24 {
            let queue = DecoderTestQueue(), release = DispatchSemaphore(value: 0)
            let request = DecoderTestRequest { _ in
                guard release.wait(timeout: .now() + 10) == .success else { throw DecoderTestError.workerFailed }
                return []
            }
            let decoder = QRDecoder(schedule: { queue.append($0) }, makeRequest: { request })
            let lifetime = DecoderFrameLifetime()
            let attempt = try makeAttempt(decoder, lifetime: lifetime)
            let task = try XCTUnwrap(attempt.task)
            defer { release.signal(); task.cancel(); queue.runAll() }
            guard await requireEventually({ queue.count == 1 }, "Decoder did not enqueue work.") else { return }
            let drained = try runWorker(queue)
            guard await requireEventually({ request.snapshots.count == 1 }, "Request did not begin.") else { return }
            DispatchQueue.global().async { task.cancel() }
            DispatchQueue.global().async { release.signal() }
            guard await requireEventually({ drained.value }, "Racing worker did not return."),
                  await waitForCompletion(attempt) else { return }
            XCTAssertTrue(attempt.outcome == .cancelled || attempt.outcome == .succeeded([]))
            XCTAssertTrue(request.cancellations <= 1)
            XCTAssertEqual(lifetime.releases, 1)
        }
    }

    private func makeAttempt(_ decoder: QRDecoder, lifetime: DecoderFrameLifetime,
                             alreadyCancelled: Bool = false) throws -> DecoderTestAttempt {
        DecoderTestAttempt(decoder: decoder, frame: try makeFrame(lifetime), alreadyCancelled: alreadyCancelled)
    }

    private func makeJob(lifetime: DecoderFrameLifetime) throws -> QRDecodeJob {
        QRDecodeJob(frame: try makeFrame(lifetime))
    }

    private func makeFrame(_ lifetime: DecoderFrameLifetime) throws -> CapturedFrame {
        let pixels = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 1)
        pixels.initializeMemory(as: UInt8.self, repeating: 255, count: 8)
        let owner = Unmanaged.passRetained(lifetime)
        guard let provider = CGDataProvider(dataInfo: owner.toOpaque(), data: pixels, size: 8,
                                            releaseData: releaseDecoderFrameData) else {
            owner.release()
            pixels.deallocate()
            throw DecoderTestError.fixtureUnavailable
        }
        let image = try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return CapturedFrame(image: image, orientation: .right)
    }

    private func runWorker(_ queue: DecoderTestQueue) throws -> DecoderTestFlag {
        let work = try XCTUnwrap(queue.takeNext())
        let drained = DecoderTestFlag()
        DispatchQueue(label: "QRSnap.tests.controlled-decoder").async {
            work()
            drained.set()
        }
        return drained
    }

    /// An outcome is recorded only after decode returns. Never await a task whose
    /// continuation may have been lost: report the failure and let cleanup release
    /// its controlled worker so the rest of the suite can still run.
    private func waitForCompletion(_ attempt: DecoderTestAttempt,
                                   file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        guard await requireEventually({ attempt.outcome != nil }, "Decoder caller did not complete.",
                                      file: file, line: line) else { return false }
        await attempt.task?.value
        return true
    }

    private func requireEventually(_ condition: () -> Bool, _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) async -> Bool {
        let observed = await eventually(condition)
        if !observed { XCTFail(message, file: file, line: line) }
        return observed
    }

    /// The gates determine execution order. This deadline only bounds a failed test;
    /// it is not a decoder timing or performance assertion.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while !condition(), clock.now < deadline { await Task.yield() }
        return condition()
    }
}

@MainActor private final class DecoderTestAttempt {
    enum Outcome: Equatable {
        case succeeded([DecodedItem]), cancelled, failed(ScanFailure?)
    }
    var outcome: Outcome?
    var task: Task<Void, Never>?

    convenience init(decoder: QRDecoder, frame: CapturedFrame, alreadyCancelled: Bool) {
        self.init {
            if alreadyCancelled { withUnsafeCurrentTask { $0?.cancel() } }
            return try await decoder.decode(frame)
        }
    }

    init(operation: @escaping @Sendable () async throws -> [DecodedItem]) {
        task = Task { [weak self] in
            do {
                let items = try await operation()
                self?.outcome = .succeeded(items)
            }
            catch is CancellationError { self?.outcome = .cancelled }
            catch { self?.outcome = .failed(error as? ScanFailure) }
        }
    }
}

private enum DecoderTestError: Error { case workerFailed, fixtureUnavailable }

/// Core Graphics releases the provider on whichever thread drops the last image
/// reference. A closure created inside the MainActor test helper can inherit that
/// isolation and trap when Core Graphics calls it from the decoder worker.
private nonisolated func releaseDecoderFrameData(_ info: UnsafeMutableRawPointer?,
                                                _ data: UnsafeRawPointer, _ size: Int) {
    UnsafeMutableRawPointer(mutating: data).deallocate()
    if let info { Unmanaged<DecoderFrameLifetime>.fromOpaque(info).takeRetainedValue().released() }
}

private final class DecoderFrameLifetime: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)
    var releases: Int { count.withLock { $0 } }
    func released() { count.withLock { $0 += 1 } }
}

private final class DecoderTestFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)
    var value: Bool { state.withLock { $0 } }
    func set() { state.withLock { $0 = true } }
}

private final class DecoderTestQueue: Sendable {
    private let jobs = OSAllocatedUnfairLock(initialState: [@Sendable () -> Void]())
    var count: Int { jobs.withLock { $0.count } }
    func append(_ job: @escaping @Sendable () -> Void) { jobs.withLock { $0.append(job) } }
    func takeNext() -> (@Sendable () -> Void)? {
        jobs.withLock { $0.isEmpty ? nil : $0.removeFirst() }
    }
    func runAll() { while let job = takeNext() { job() } }
}

private final class DecoderTestRequest: QRDecodeRequest {
    struct Snapshot: Equatable, Sendable {
        let width: Int
        let height: Int
        let orientation: UInt32
    }
    private struct State: Sendable {
        var snapshots: [Snapshot] = []
        var cancellations = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let action: @Sendable (CapturedFrame) throws -> [DecodedItem]
    init(action: @escaping @Sendable (CapturedFrame) throws -> [DecodedItem] = { _ in [] }) { self.action = action }
    var snapshots: [Snapshot] { state.withLock { $0.snapshots } }
    var cancellations: Int { state.withLock { $0.cancellations } }
    func perform(_ frame: CapturedFrame) throws -> [DecodedItem] {
        state.withLock { $0.snapshots.append(.init(width: frame.pixelWidth, height: frame.pixelHeight,
                                                 orientation: frame.orientation.rawValue)) }
        return try action(frame)
    }
    func cancel() { state.withLock { $0.cancellations += 1 } }
}
