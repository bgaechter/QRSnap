import Foundation

/// Coordinates one scan without selecting windows, querying permission, or opening a destination.
/// Composition must explain/check permission before calling `beginSelection()`.
@MainActor public final class ScanCoordinator {
    public enum FinishReason: Equatable, Sendable {
        case cancelled
        case failed(ScanFailure)
        case openingFinished
    }

    public enum Event: Equatable, Sendable {
        case selecting(UUID)
        /// Capture has started. This does not require hiding the excluded selection overlay.
        case processing(UUID)
        case progress(UUID, isVisible: Bool)
        /// One event per successful decode, preserving every physical observation and optional payload.
        case results(UUID, [DecodedItem])
        /// Release this session's overlays, cursor, observers, previews, and other UI resources.
        /// Events carry their token because handlers may synchronously start another session.
        case finished(UUID, FinishReason)
    }

    public var sessionID: UUID? { lifecycle.id }
    public var phase: SessionLifecycle.Phase { lifecycle.phase }
    public private(set) var results: [DecodedItem] = []

    private var lifecycle = SessionLifecycle()
    private let capture: any ScreenCapturing
    private let decoder: any QRDecoding
    private let progressDelay: Duration
    private let timeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let onEvent: @MainActor (Event) -> Void
    private var workTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var progressVisible = false

    public init(capture: any ScreenCapturing, decoder: any QRDecoding,
                progressDelay: Duration = .milliseconds(300), timeout: Duration = .seconds(5),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                onEvent: @escaping @MainActor (Event) -> Void) {
        precondition(progressDelay >= .zero && timeout > .zero && progressDelay < timeout)
        self.capture = capture
        self.decoder = decoder
        self.progressDelay = progressDelay
        self.timeout = timeout
        self.sleep = sleep
        self.onEvent = onEvent
    }

    deinit {
        workTask?.cancel()
        progressTask?.cancel()
        timeoutTask?.cancel()
    }

    /// Returns nil while busy. Drag time and permission prompts are outside the processing deadline.
    @discardableResult public func beginSelection() -> UUID? {
        guard let token = lifecycle.begin() else { return nil }
        onEvent(.selecting(token))
        // Selection handlers may synchronously cancel or replace the session. Do not
        // authorize the caller to present an overlay for a token that is already stale.
        return lifecycle.contains(token) ? token : nil
    }

    /// Accepts a selection once, and only from the active session.
    @discardableResult public func submit(_ selection: Selection) -> Bool {
        let token = selection.sessionID
        guard lifecycle.advance(token, from: .selecting, to: .capturing) else { return false }
        let capture = self.capture, decoder = self.decoder
        // Capture's OS boundary is main-actor isolated. The decoder owns its worker queue;
        // the coordinator never performs synchronous Vision work on the main actor.
        workTask = Task { [weak self] in
            guard self?.isProcessing(token) == true else { return }
            do {
                let frame = try await capture.capture(selection)
                guard self?.lifecycle.advance(token, from: .capturing, to: .decoding) == true else { return }
                let items = try await decoder.decode(frame)
                self?.didDecode(items, sessionID: token)
            } catch is CancellationError {
                self?.finish(token, reason: .cancelled)
            } catch {
                guard let owner = self, owner.isProcessing(token) else { return }
                let fallback: ScanFailure = owner.phase == .capturing ? .captureFailed : .decodeFailed
                owner.finish(token, reason: .failed(error as? ScanFailure ?? fallback))
            }
        }
        startTimers(token)
        onEvent(.processing(token))
        return true
    }

    /// Invalidates callbacks immediately; cancellation cannot retract an external handoff already made.
    @discardableResult public func cancel(sessionID: UUID) -> Bool {
        finish(sessionID, reason: .cancelled)
    }

    @discardableResult public func displayDidChange(sessionID: UUID) -> Bool {
        finish(sessionID, reason: .failed(.displayChanged))
    }

    /// Claim once, at the handoff boundary. This method does not launch anything.
    /// If the caller awaits after claiming, it must recheck the current token and `.opening`
    /// immediately before invoking its launcher. A cancelled claim is never still valid.
    @discardableResult public func claimOpening(sessionID: UUID) -> Bool {
        lifecycle.advance(sessionID, from: .reviewing, to: .opening)
    }

    /// Called after the launcher reports its result. The caller owns any handoff error UI.
    @discardableResult public func finishOpening(sessionID: UUID) -> Bool {
        guard lifecycle.contains(sessionID), phase == .opening else { return false }
        return finish(sessionID, reason: .openingFinished)
    }

    /// Ends result handling, including failures before a launcher was called.
    /// Composition retains any original text/document needed by its recovery UI.
    @discardableResult public func failResult(sessionID: UUID, failure: ScanFailure) -> Bool {
        guard lifecycle.contains(sessionID), phase == .reviewing || phase == .opening else { return false }
        return finish(sessionID, reason: .failed(failure))
    }

    private func isProcessing(_ token: UUID) -> Bool {
        lifecycle.contains(token) && (phase == .capturing || phase == .decoding)
    }

    private func startTimers(_ token: UUID) {
        let sleep = self.sleep, progressDelay = self.progressDelay, timeout = self.timeout
        progressTask = Task { [weak self] in
            do { try await sleep(progressDelay) } catch { return }
            guard !Task.isCancelled, let owner = self, owner.isProcessing(token) else { return }
            owner.progressVisible = true
            owner.onEvent(.progress(token, isVisible: true))
        }
        timeoutTask = Task { [weak self] in
            do { try await sleep(timeout) } catch { return }
            guard !Task.isCancelled, let owner = self, owner.isProcessing(token) else { return }
            owner.finish(token, reason: .failed(.timedOut))
        }
    }

    private func didDecode(_ items: [DecodedItem], sessionID: UUID) {
        guard lifecycle.advance(sessionID, from: .decoding, to: .reviewing) else { return }
        stopTimers()
        workTask = nil
        guard !items.isEmpty else {
            finish(sessionID, reason: .failed(.noQR))
            return
        }
        results = items
        if progressVisible {
            progressVisible = false
            onEvent(.progress(sessionID, isVisible: false))
        }
        // An event handler may cancel/retry synchronously, so validate again before publishing.
        guard lifecycle.contains(sessionID), phase == .reviewing else { return }
        onEvent(.results(sessionID, items))
    }

    @discardableResult private func finish(_ token: UUID, reason: FinishReason) -> Bool {
        guard lifecycle.finish(token) else { return false }
        workTask?.cancel()
        workTask = nil
        stopTimers()
        results = []
        progressVisible = false
        // The terminal event also hides progress; there is no intermediate callback that can
        // observe partially cleaned state. Already-running OS work may finish later and is ignored.
        onEvent(.finished(token, reason))
        return true
    }

    private func stopTimers() {
        progressTask?.cancel()
        progressTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}
