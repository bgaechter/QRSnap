import Foundation

/// Composes scan lifecycle and payload policy without owning windows or permission UI.
/// The host must check permission before beginning, and supply a launcher that rechecks
/// the factory's validity predicate at its actual OS boundary (WorkspacePayloadLauncher does).
@MainActor public final class ScanWorkflow {
    public struct ActionRequest: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case confirmExternal(URL, HandlerMetadata)
            case openBlockedAsText
        }

        /// A fresh ID for each prompt, including a replacement-handler confirmation.
        public let id: UUID
        public let sessionID: UUID
        public let observation: DecodedItem
        public let kind: Kind
    }

    public enum Outcome: Equatable, Sendable {
        case cancelled
        case handoffSucceeded
        /// Original text and any completed document survive for later Copy/Save UI.
        case failed(ScanFailure, retainedText: String?, documentURL: URL?)
    }

    public enum Event: Equatable, Sendable {
        case selecting(UUID)
        case processing(UUID)
        case progress(UUID, isVisible: Bool)
        /// Every physical observation remains a separate choice, including duplicates/nil text.
        case choose(UUID, [DecodedItem])
        case actionRequired(ActionRequest)
        /// Release this session's UI; a callback may immediately begin another scan.
        case finished(UUID, Outcome)
    }

    public typealias LauncherFactory = @MainActor (@escaping @MainActor () -> Bool) -> any PayloadLaunching

    public var sessionID: UUID? { coordinator.sessionID }
    public var phase: SessionLifecycle.Phase { coordinator.phase }

    private var coordinator: ScanCoordinator!
    private let textStore: any TextDocumentStoring
    private let makeLauncher: LauncherFactory
    private let onEvent: @MainActor (Event) -> Void
    private var choices: [DecodedItem] = []
    private var selected: (observation: DecodedItem, dispatcher: PayloadDispatcher, payload: PreparedPayload)?
    private var request: ActionRequest?
    private var dispatchTask: Task<Void, Never>?
    private var terminalOutcome: Outcome?

    public init(capture: any ScreenCapturing, decoder: any QRDecoding,
                textStore: any TextDocumentStoring, makeLauncher: @escaping LauncherFactory,
                progressDelay: Duration = .milliseconds(300), timeout: Duration = .seconds(5),
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                onEvent: @escaping @MainActor (Event) -> Void) {
        self.textStore = textStore
        self.makeLauncher = makeLauncher
        self.onEvent = onEvent
        coordinator = ScanCoordinator(capture: capture, decoder: decoder, progressDelay: progressDelay,
                                      timeout: timeout, sleep: sleep) { [weak self] event in
            self?.receive(event)
        }
    }

    deinit { dispatchTask?.cancel() }

    @discardableResult public func beginSelection() -> UUID? { coordinator.beginSelection() }
    @discardableResult public func submit(_ selection: Selection) -> Bool { coordinator.submit(selection) }
    @discardableResult public func cancel(sessionID: UUID) -> Bool { coordinator.cancel(sessionID: sessionID) }
    @discardableResult public func displayDidChange(sessionID: UUID) -> Bool {
        coordinator.displayDidChange(sessionID: sessionID)
    }

    /// Locks the chosen observation before any callback or asynchronous operation.
    @discardableResult public func choose(sessionID token: UUID, observationID: Int) -> Bool {
        guard sessionID == token, phase == .reviewing,
              let observation = choices.first(where: { $0.id == observationID }) else { return false }
        choices = []
        let isCurrent: @MainActor () -> Bool = { [weak self] in self?.isCurrent(token) == true }
        let destination = makeLauncher(isCurrent)
        let launcher = WorkflowLauncher(destination: destination, isCurrent: isCurrent) { [weak self] in
            self?.coordinator.claimOpening(sessionID: token) == true
        }
        let dispatcher = PayloadDispatcher(launcher: launcher, textStore: textStore)
        // Factories and handler queries may synchronously cancel/restart the scan.
        guard let payload = dispatcher.prepare(observation.payload, isCurrent: isCurrent) else {
            // Preparation can also stop because the caller's Task was cancelled.
            // Do not strand an otherwise-current scan after consuming its choices.
            if isCurrent() { coordinator.cancel(sessionID: token) }
            return false
        }
        guard isCurrent() else { return false }
        selected = (observation, dispatcher, payload)
        dispatch(.automatic, sessionID: token)
        return true
    }

    @discardableResult public func confirm(requestID: UUID) -> Bool {
        guard let request, request.id == requestID, case .confirmExternal = request.kind else { return false }
        return act(.openExternal, request: request)
    }

    /// Explicit fallback for a blocked URI or an external URI the user elects to read as text.
    @discardableResult public func openAsText(requestID: UUID) -> Bool {
        guard let request, request.id == requestID else { return false }
        return act(.openAsText, request: request)
    }

    private func act(_ action: PayloadDispatchAction, request: ActionRequest) -> Bool {
        guard sessionID == request.sessionID, phase == .reviewing, dispatchTask == nil else { return false }
        guard !Task.isCancelled else {
            coordinator.cancel(sessionID: request.sessionID)
            return false
        }
        self.request = nil // Consume this prompt before scheduling, including rapid double clicks.
        dispatch(action, sessionID: request.sessionID)
        return true
    }

    private func isCurrent(_ token: UUID) -> Bool {
        sessionID == token && (phase == .reviewing || phase == .opening)
    }

    private func dispatch(_ action: PayloadDispatchAction, sessionID token: UUID) {
        guard let selected, isCurrent(token), dispatchTask == nil else { return }
        let dispatcher = selected.dispatcher, payload = selected.payload
        dispatchTask = Task { [weak self] in
            let outcome = await dispatcher.dispatch(payload, action: action) { [weak self] in
                self?.isCurrent(token) == true
            }
            guard !Task.isCancelled else { return }
            self?.didDispatch(outcome, sessionID: token)
        }
    }

    private func didDispatch(_ outcome: PayloadDispatchOutcome, sessionID token: UUID) {
        guard isCurrent(token), let selected else { return }
        dispatchTask = nil
        switch outcome {
        case .handoffSucceeded:
            coordinator.finishOpening(sessionID: token)
        case .confirmationRequired(let handler):
            guard case .confirmedExternalURI(let url, _) = selected.payload.route else { return }
            publishRequest(.confirmExternal(url, handler), token: token, observation: selected.observation)
        case .explicitTextActionRequired:
            publishRequest(.openBlockedAsText, token: token, observation: selected.observation)
        case .failure(let failure, let text, let documentURL):
            fail(failure, token: token, text: text, documentURL: documentURL)
        case .unsupported(let failure):
            fail(failure, token: token, text: selected.payload.original, documentURL: nil)
        case .cancelled:
            coordinator.cancel(sessionID: token)
        case .actionUnavailable, .alreadyDispatched:
            // Public actions are gated above; still terminate if a future adapter violates the contract.
            fail(.launchFailed, token: token, text: selected.payload.original, documentURL: nil)
        }
    }

    private func publishRequest(_ kind: ActionRequest.Kind, token: UUID, observation: DecodedItem) {
        let request = ActionRequest(id: UUID(), sessionID: token, observation: observation, kind: kind)
        self.request = request
        onEvent(.actionRequired(request))
    }

    private func fail(_ failure: ScanFailure, token: UUID, text: String?, documentURL: URL?) {
        terminalOutcome = .failed(failure, retainedText: text, documentURL: documentURL)
        coordinator.failResult(sessionID: token, failure: failure)
    }

    private func receive(_ event: ScanCoordinator.Event) {
        switch event {
        case .selecting(let token): onEvent(.selecting(token))
        case .processing(let token): onEvent(.processing(token))
        case .progress(let token, let visible): onEvent(.progress(token, isVisible: visible))
        case .results(let token, let items):
            choices = items
            if items.count == 1 { choose(sessionID: token, observationID: items[0].id) }
            else { onEvent(.choose(token, items)) }
        case .finished(let token, let reason):
            let outcome: Outcome
            switch reason {
            case .cancelled: outcome = .cancelled
            case .openingFinished: outcome = .handoffSucceeded
            case .failed(let failure):
                outcome = terminalOutcome ?? .failed(failure, retainedText: nil, documentURL: nil)
            }
            dispatchTask?.cancel()
            dispatchTask = nil
            choices = []
            selected = nil
            request = nil
            terminalOutcome = nil
            onEvent(.finished(token, outcome))
        }
    }
}

/// The coordinator's one-time opening claim belongs at the launch boundary, after
/// confirmation, handler resolution and storage. It is not a repeatable validity predicate.
@MainActor private final class WorkflowLauncher: PayloadLaunching {
    private let destination: any PayloadLaunching
    private let isCurrent: @MainActor () -> Bool
    private let claimOpening: @MainActor () -> Bool

    init(destination: any PayloadLaunching, isCurrent: @escaping @MainActor () -> Bool,
         claimOpening: @escaping @MainActor () -> Bool) {
        self.destination = destination
        self.isCurrent = isCurrent
        self.claimOpening = claimOpening
    }

    func handler(for url: URL) -> HandlerMetadata? {
        guard !Task.isCancelled, isCurrent() else { return nil }
        return destination.handler(for: url)
    }

    func open(_ url: URL) async -> LaunchResult {
        guard !Task.isCancelled, isCurrent(), claimOpening() else { return .failure(.launchFailed) }
        return await destination.open(url)
    }
}
