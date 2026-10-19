import Foundation
import Vision
import os

public final class QRDecoder: QRDecoding, Sendable {
    typealias Schedule = @Sendable (@escaping @Sendable () -> Void) -> Void
    typealias RequestFactory = @Sendable () -> any QRDecodeRequest

    private let schedule: Schedule
    private let makeRequest: RequestFactory

    public convenience init() {
        let queue = DispatchQueue(label: "QRSnap.vision", qos: .userInitiated)
        self.init(schedule: { queue.async(execute: $0) }, makeRequest: { VisionQRDecodeRequest() })
    }

    /// Keep the native serial scheduler and each request replaceable for deterministic
    /// cancellation tests. No test has to start Vision or race a real image analysis.
    init(schedule: @escaping Schedule, makeRequest: @escaping RequestFactory) {
        self.schedule = schedule
        self.makeRequest = makeRequest
    }

    public func decode(_ frame: CapturedFrame) async throws -> [DecodedItem] {
        try Task.checkCancellation()
        let job = QRDecodeJob(frame: frame)
        let schedule = self.schedule, makeRequest = self.makeRequest
        return try await withTaskCancellationHandler {
            let result: [DecodedItem] = try await withCheckedThrowingContinuation { continuation in
                guard job.install(continuation) else { return }
                // The queue retains only the job, whose frame can be cleared on
                // cancellation. Capturing `frame` here would retain cancelled pixels.
                schedule { job.run(makeRequest: makeRequest) }
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            job.cancel()
        }
    }
}

/// A request is configured and performed once on the decoder's serial worker.
/// Its cancellation method must support a concurrent call from task cancellation.
protocol QRDecodeRequest: Sendable {
    func perform(_ frame: CapturedFrame) throws -> [DecodedItem]
    func cancel()
}

/// Only this per-request adapter bridges Vision's older, non-Sendable class.
/// Configuration, perform and result access stay on its one worker; the only
/// concurrent operation is VNRequest.cancel(), the documented cancellation API.
/// The request is never reused or exposed to other jobs.
/// https://developer.apple.com/documentation/vision/vnrequest/cancel()
private final class VisionQRDecodeRequest: QRDecodeRequest, @unchecked Sendable {
    private let request: VNDetectBarcodesRequest

    init() {
        request = VNDetectBarcodesRequest()
        request.revision = VNDetectBarcodesRequestRevision4
        request.symbologies = [.qr]
    }

    func perform(_ frame: CapturedFrame) throws -> [DecodedItem] {
        let handler = VNImageRequestHandler(cgImage: frame.image, orientation: frame.orientation)
        try handler.perform([request])
        return (request.results ?? []).enumerated().map {
            DecodedItem(id: $0.offset, payload: $0.element.payloadStringValue,
                        bounds: $0.element.boundingBox)
        }
    }

    func cancel() { request.cancel() }
}

/// A cancelled caller resumes without waiting for its queue position or Vision.
/// Jobs cancelled before the worker claims their frame release it and skip perform.
/// A claimed job is active, including the interval before perform begins. Native
/// cancellation is cooperative; active work can retain its frame until it returns.
final class QRDecodeJob: Sendable {
    private struct State: Sendable {
        var frame: CapturedFrame?
        var continuation: CheckedContinuation<[DecodedItem], Error>?
        var request: (any QRDecodeRequest)?
        var finished = false
    }

    private let state: OSAllocatedUnfairLock<State>

    init(frame: CapturedFrame) { state = OSAllocatedUnfairLock(initialState: State(frame: frame)) }

    func install(_ continuation: CheckedContinuation<[DecodedItem], Error>) -> Bool {
        let installed = state.withLock { value in
            guard !value.finished else { return false }
            value.continuation = continuation
            return true
        }
        // onCancel can run before withCheckedThrowingContinuation is entered.
        if !installed { continuation.resume(throwing: CancellationError()) }
        return installed
    }

    func run(makeRequest: QRDecoder.RequestFactory) {
        guard state.withLock({ !$0.finished && $0.frame != nil }) else { return }
        let outcome: Result<[DecodedItem], Error>? = autoreleasepool {
            // Do not take the frame until the request is ready. Cancellation can
            // still release queued pixels while a request factory is in progress.
            let request = makeRequest()
            let frame = state.withLock { value -> CapturedFrame? in
                guard !value.finished, let frame = value.frame else { return nil }
                value.frame = nil
                value.request = request
                return frame
            }
            guard let frame else { return nil }
            do {
                return .success(GeometryAdapter.readingOrder(try request.perform(frame)))
            } catch {
                return .failure(ScanFailure.decodeFailed)
            }
        }
        if let outcome { finish(outcome, cancelling: false) }
    }

    func cancel() { finish(.failure(CancellationError()), cancelling: true) }

    private func finish(_ outcome: Result<[DecodedItem], Error>, cancelling: Bool) {
        let released = state.withLock { value -> State? in
            guard !value.finished else { return nil }
            let previous = value
            value = State(finished: true)
            return previous
        }
        guard let released else { return }
        // Never resume, invoke cancellation, or destroy the last image reference
        // under the lock: cancellation and framework cleanup can be reentrant.
        // Swift's cancellation-handler documentation specifically warns against
        // resuming a continuation while holding a lock shared with onCancel.
        released.continuation?.resume(with: outcome)
        if cancelling { released.request?.cancel() }
        withExtendedLifetime(released) {}
    }
}
