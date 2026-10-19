import AppKit

/// Production composition: permission is checked only on an explicit scan action.
/// Screenshots remain owned by the workflow and are never persisted by this controller.
@MainActor final class ScanApplicationController {
    struct SelectionUI {
        var show: @MainActor (UUID, @escaping @MainActor (Result<Selection?, ScanFailure>) -> Void,
                              @escaping @MainActor () -> Void, @escaping @MainActor () -> Void) -> Void
        var close: @MainActor () -> Void
    }

    /// Monitoring outlives the selection panels so Escape and display changes also
    /// invalidate decoding, result review, and an outstanding handoff callback.
    struct SessionEvents {
        var observe: @MainActor (@escaping @MainActor () -> Void,
                                 @escaping @MainActor () -> Void) -> (@MainActor () -> Void)

        static var native: SessionEvents {
            SessionEvents { cancel, displayChanged in
                let keyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.keyCode == 53 else { return event }
                    return MainActor.assumeIsolated {
                        let window = event.window ?? NSApp.keyWindow
                        // A native Save sheet owns Escape while it is open. Cancelling
                        // Save must preserve the scanned text in its result window.
                        guard handlesEscape(hasModalWindow: NSApp.modalWindow != nil,
                                            hasSheet: window?.sheetParent != nil || window?.attachedSheet != nil) else {
                            return event
                        }
                        cancel()
                        return nil
                    }
                }
                let screen = NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
                ) { _ in MainActor.assumeIsolated { displayChanged() } }
                return {
                    if let keyboard { NSEvent.removeMonitor(keyboard) }
                    NotificationCenter.default.removeObserver(screen)
                }
            }
        }

        static func handlesEscape(hasModalWindow: Bool, hasSheet: Bool) -> Bool {
            !hasModalWindow && !hasSheet
        }
    }

    var sessionID: UUID? { activeToken }
    var phase: SessionLifecycle.Phase { workflow.phase }
    private(set) var resultWindowController: ScanResultWindowController!

    private let permission: any ScreenPermissionChecking
    private let selection: SelectionUI
    private let sessionEvents: SessionEvents
    private let showPermissionExplanation: @MainActor () -> Void
    private let beforeSelection: @MainActor () -> Void
    private let onProgress: @MainActor (Bool) -> Void
    private let onEvent: @MainActor (ScanWorkflow.Event) -> Void
    private var workflow: ScanWorkflow!
    private var activeToken: UUID?
    private var presentationToken: UUID?
    private var recoveryToken: UUID?
    private var overlayToken: UUID?
    private var stopObserving: (@MainActor () -> Void)?
    private var checkingPermission = false

    init(permission: any ScreenPermissionChecking, capture: any ScreenCapturing, decoder: any QRDecoding,
         textStore: any TextDocumentStoring, makeLauncher: @escaping ScanWorkflow.LauncherFactory,
         selection: SelectionUI, sessionEvents: SessionEvents = .native,
         textActions: ScanResultWindowController.TextActions = .native, presentsWindows: Bool = true,
         progressDelay: Duration = .milliseconds(300), timeout: Duration = .seconds(5),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         showPermissionExplanation: @escaping @MainActor () -> Void,
         beforeSelection: @escaping @MainActor () -> Void = {},
         onProgress: @escaping @MainActor (Bool) -> Void = { _ in },
         onEvent: @escaping @MainActor (ScanWorkflow.Event) -> Void = { _ in }) {
        self.permission = permission
        self.selection = selection
        self.sessionEvents = sessionEvents
        self.showPermissionExplanation = showPermissionExplanation
        self.beforeSelection = beforeSelection
        self.onProgress = onProgress
        self.onEvent = onEvent
        resultWindowController = ScanResultWindowController(textActions: textActions, presentsWindows: presentsWindows) {
            [weak self] action in self?.perform(action)
        }
        let captured = ApplicationCapture(destination: capture) { [weak self] token in
            self?.closeSelection(sessionID: token)
        }
        workflow = ScanWorkflow(capture: captured, decoder: decoder, textStore: textStore, makeLauncher: makeLauncher,
                                progressDelay: progressDelay, timeout: timeout, sleep: sleep) { [weak self] event in
            self?.receive(event)
        }
    }

    /// Repeated activation while busy is ignored. The host explains access and may
    /// call permission.request() only after the user's explicit consent in its UI.
    @discardableResult func startScan() -> Bool {
        guard activeToken == nil, !checkingPermission else { return false }
        guard permissionAvailable() else { return false }
        return workflow.beginSelection() != nil
    }

    private func permissionAvailable() -> Bool {
        checkingPermission = true
        defer { checkingPermission = false }
        guard permission.isGranted else { showPermissionExplanation(); return false }
        return true
    }

    /// Also dismisses retained terminal recovery. Call on application termination.
    func cancel() {
        if let token = activeToken { cancel(sessionID: token) }
        else {
            recoveryToken = nil
            presentationToken = nil
            resultWindowController.dismiss()
            onProgress(false)
        }
    }

    func shutdown() { cancel() }

    func displayDidChange() {
        if let token = activeToken { displayDidChange(sessionID: token) }
    }

    private func cancel(sessionID token: UUID) {
        guard activeToken == token else { return }
        workflow.cancel(sessionID: token)
    }

    private func displayDidChange(sessionID token: UUID) {
        guard activeToken == token else { return }
        workflow.displayDidChange(sessionID: token)
    }

    private func selected(_ result: Result<Selection?, ScanFailure>, sessionID token: UUID) {
        guard activeToken == token, workflow.phase == .selecting else { return }
        switch result {
        case .success(let region?):
            guard region.sessionID == token else { return }
            workflow.submit(region)
        case .success(nil): workflow.cancel(sessionID: token)
        case .failure(let failure): workflow.failSelection(sessionID: token, failure: failure)
        }
    }

    private func closeSelection(sessionID token: UUID) {
        guard overlayToken == token else { return }
        // Clear ownership before calling an adapter that can synchronously reenter.
        overlayToken = nil
        selection.close()
    }

    private func receive(_ event: ScanWorkflow.Event) {
        switch event {
        case .selecting(let token):
            activeToken = token
            presentationToken = token
            recoveryToken = nil
            resultWindowController.receive(event)
            guard activeToken == token else { return }
            beforeSelection()
            guard activeToken == token else { return }
            let stop = sessionEvents.observe({ [weak self] in self?.cancel(sessionID: token) },
                                             { [weak self] in self?.displayDidChange(sessionID: token) })
            guard activeToken == token else { stop(); return }
            stopObserving = stop
            onProgress(false)
            guard activeToken == token else { return }
            onEvent(event)
            guard activeToken == token else { return }
            overlayToken = token
            selection.show(token, { [weak self] result in self?.selected(result, sessionID: token) },
                           { [weak self] in self?.cancel(sessionID: token) },
                           { [weak self] in self?.displayDidChange(sessionID: token) })
        case .processing(let token):
            guard activeToken == token else { return }
            onEvent(event)
        case .progress(let token, let visible):
            guard activeToken == token else { return }
            onProgress(visible)
            guard activeToken == token else { return }
            onEvent(event)
        case .choose(let token, _):
            present(event, sessionID: token)
        case .actionRequired(let request):
            present(event, sessionID: request.sessionID)
        case .finished(let token, let outcome):
            guard activeToken == token else { return }
            activeToken = nil
            if case .failed = outcome { recoveryToken = token } else { recoveryToken = nil }
            let stop = stopObserving
            stopObserving = nil
            closeSelection(sessionID: token)
            stop?()
            // Cleanup adapters and callbacks may immediately begin another scan.
            guard presentationToken == token else { return }
            resultWindowController.receive(event)
            guard presentationToken == token else { return }
            onProgress(false)
            guard presentationToken == token else { return }
            onEvent(event)
        }
    }

    private func present(_ event: ScanWorkflow.Event, sessionID token: UUID) {
        guard activeToken == token else { return }
        closeSelection(sessionID: token)
        guard activeToken == token else { return }
        resultWindowController.receive(event)
        guard activeToken == token else { return }
        onEvent(event)
    }

    /// Window actions carry session/request identities; the workflow provides the
    /// final one-shot checks immediately before storage and external dispatch.
    func perform(_ action: ScanResultWindowController.Action) {
        switch action {
        case .choose(let token, let observationID):
            guard activeToken == token else { return }
            workflow.choose(sessionID: token, observationID: observationID)
        case .confirm(let requestID): workflow.confirm(requestID: requestID)
        case .openAsText(let requestID): workflow.openAsText(requestID: requestID)
        case .cancel(let token):
            if activeToken == token { cancel(sessionID: token) }
            else if recoveryToken == token { cancel() }
        case .retry(let token):
            guard activeToken == nil, recoveryToken == token, presentationToken == token else { return }
            recoveryToken = nil
            resultWindowController.dismiss()
            startScan()
        }
    }
}

/// Removes selection chrome as soon as capture ends, including errors. Keeping the
/// callback outside the frame prevents this adapter from retaining screenshot data.
@MainActor private final class ApplicationCapture: ScreenCapturing {
    private let destination: any ScreenCapturing
    private let finished: @MainActor (UUID) -> Void

    init(destination: any ScreenCapturing, finished: @escaping @MainActor (UUID) -> Void) {
        self.destination = destination
        self.finished = finished
    }

    func capture(_ selection: Selection) async throws -> CapturedFrame {
        defer { finished(selection.sessionID) }
        return try await destination.capture(selection)
    }
}
