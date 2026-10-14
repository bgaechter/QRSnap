import Foundation

public enum PayloadDispatchAction: Sendable {
    case automatic
    case openExternal
    case openAsText
}

public enum PayloadDispatchOutcome: Equatable, Sendable {
    case handoffSucceeded
    case confirmationRequired(HandlerMetadata)
    case explicitTextActionRequired
    case actionUnavailable
    case cancelled
    case alreadyDispatched
    case unsupported(ScanFailure)
    case failure(ScanFailure, retainedText: String, documentURL: URL?)
}

/// One selected observation. Keep this object for every action in its result UI;
/// preparing a new object deliberately starts a new dispatch attempt.
@MainActor public final class PreparedPayload {
    public private(set) var route: Route
    public let original: String?
    fileprivate let owner: UUID
    fileprivate var consumed = false

    fileprivate init(route: Route, original: String?, owner: UUID) {
        self.route = route
        self.original = original
        self.owner = owner
    }

    fileprivate func updateHandler(url: URL, handler: HandlerMetadata) {
        route = .confirmedExternalURI(url, handler)
    }
}

/// Independent policy boundary. The app must deliberately invoke dispatch after
/// selecting an observation; classification and preparation never launch or write.
@MainActor public final class PayloadDispatcher {
    private let launcher: any PayloadLaunching
    private let textStore: any TextDocumentStoring
    private let identity = UUID()

    public init(launcher: any PayloadLaunching, textStore: any TextDocumentStoring) {
        self.launcher = launcher
        self.textStore = textStore
    }

    public func prepare(_ original: String?, isCurrent: () -> Bool) -> PreparedPayload? {
        guard !Task.isCancelled, isCurrent() else { return nil }
        let route: Route
        switch PayloadClassifier.classify(original) {
        case .webURL(let url): route = .webURL(url)
        case .externalCandidate(let url):
            guard !Task.isCancelled, isCurrent() else { return nil }
            let handler = launcher.handler(for: url)
            guard !Task.isCancelled, isCurrent() else { return nil }
            if let handler { route = .confirmedExternalURI(url, handler) }
            else if let original { route = .plainText(original) }
            else { route = .unsupported(.unsupportedPayload) }
        case .plainText(let text): route = .plainText(text)
        case .blockedText(let text): route = .blockedText(text)
        case .unsupported: route = .unsupported(.unsupportedPayload)
        }
        return PreparedPayload(route: route, original: original, owner: identity)
    }

    public func dispatch(_ prepared: PreparedPayload,
                         action: PayloadDispatchAction = .automatic,
                         isCurrent: () -> Bool) async -> PayloadDispatchOutcome {
        guard prepared.owner == identity else { return .actionUnavailable }
        guard !prepared.consumed else { return .alreadyDispatched }
        guard !Task.isCancelled, isCurrent() else {
            prepared.consumed = true
            return .cancelled
        }
        if case .unsupported(let reason) = prepared.route { return .unsupported(reason) }
        // Every supported classifier result has its unmodified original string.
        guard let original = prepared.original else { return .unsupported(.unsupportedPayload) }

        if action == .openAsText {
            return await openText(original, prepared: prepared, isCurrent: isCurrent)
        }
        switch prepared.route {
        case .webURL(let url):
            guard action == .automatic else { return .actionUnavailable }
            prepared.consumed = true
            return await open(url, original: original, documentURL: nil, isCurrent: isCurrent)
        case .plainText:
            guard action == .automatic else { return .actionUnavailable }
            return await openText(original, prepared: prepared, isCurrent: isCurrent)
        case .blockedText:
            return action == .automatic ? .explicitTextActionRequired : .actionUnavailable
        case .confirmedExternalURI(let url, let approvedHandler):
            guard action == .openExternal else { return .confirmationRequired(approvedHandler) }
            guard !Task.isCancelled, isCurrent() else {
                prepared.consumed = true
                return .cancelled
            }
            let currentHandler = launcher.handler(for: url)
            guard !Task.isCancelled, isCurrent() else {
                prepared.consumed = true
                return .cancelled
            }
            guard let currentHandler else {
                prepared.consumed = true
                return .failure(.handlerUnavailable, retainedText: original, documentURL: nil)
            }
            guard currentHandler == approvedHandler else {
                prepared.updateHandler(url: url, handler: currentHandler)
                return .confirmationRequired(currentHandler)
            }
            prepared.consumed = true
            // Handler was checked in this main-actor turn; open checks validity again.
            return await open(url, original: original, documentURL: nil,
                              checkHandler: false, isCurrent: isCurrent)
        case .unsupported(let reason): return .unsupported(reason)
        }
    }

    private func openText(_ original: String, prepared: PreparedPayload,
                          isCurrent: () -> Bool) async -> PayloadDispatchOutcome {
        prepared.consumed = true
        guard !Task.isCancelled, isCurrent() else { return .cancelled }
        let documentURL: URL
        do { documentURL = try textStore.createDocument(text: original) }
        catch {
            guard !Task.isCancelled, isCurrent() else { return .cancelled }
            return .failure(.fileWriteFailed, retainedText: original, documentURL: nil)
        }
        // A successful write is retained even if the session ends during storage.
        guard !Task.isCancelled, isCurrent() else { return .cancelled }
        return await open(documentURL, original: original, documentURL: documentURL, isCurrent: isCurrent)
    }

    private func open(_ url: URL, original: String, documentURL: URL?,
                      checkHandler: Bool = true, isCurrent: () -> Bool) async -> PayloadDispatchOutcome {
        guard !Task.isCancelled, isCurrent() else { return .cancelled }
        if checkHandler {
            let handler = launcher.handler(for: url)
            guard !Task.isCancelled, isCurrent() else { return .cancelled }
            guard handler != nil else {
                return .failure(.handlerUnavailable, retainedText: original, documentURL: documentURL)
            }
        }
        guard !Task.isCancelled, isCurrent() else { return .cancelled }
        let result = await launcher.open(url)
        // Cancellation cannot retract an NSWorkspace request already submitted.
        guard !Task.isCancelled, isCurrent() else { return .cancelled }
        switch result {
        case .handoffSucceeded: return .handoffSucceeded
        case .failure(let reason):
            return .failure(reason, retainedText: original, documentURL: documentURL)
        }
    }
}
