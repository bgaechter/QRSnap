import AppKit
import UniformTypeIdentifiers

/// Native result presentation only. The host owns the workflow and its permission checks.
/// Payload values remain in memory and are never used as filenames or diagnostic messages.
@MainActor final class ScanResultWindowController: NSObject, NSWindowDelegate {
    enum Action: Equatable {
        case choose(sessionID: UUID, observationID: Int)
        case confirm(requestID: UUID)
        case openAsText(requestID: UUID)
        case cancel(sessionID: UUID)
        case retry(sessionID: UUID)
    }

    /// The three native side effects are injectable without replacing the actual controls.
    struct TextActions {
        var copy: @MainActor (String) -> Bool
        var chooseSaveURL: @MainActor (NSWindow, @escaping @MainActor (URL?) -> Void) -> (@MainActor () -> Void)
        var write: @MainActor (String, URL) throws -> Void

        static var native: TextActions {
            TextActions(copy: { text in
                NSPasteboard.general.clearContents()
                return NSPasteboard.general.setString(text, forType: .string)
            }, chooseSaveURL: { window, completion in
                let panel = NSSavePanel()
                panel.title = "Save scanned text"
                panel.nameFieldStringValue = "Scanned Text.txt"
                panel.allowedContentTypes = [.plainText]
                panel.canCreateDirectories = true
                panel.beginSheetModal(for: window) { response in
                    completion(response == .OK ? panel.url : nil)
                }
                return { panel.cancel(nil) }
            }, write: { text, url in
                try Data(text.utf8).write(to: url, options: .atomic)
            })
        }
    }

    private final class Presentation {
        let id = UUID()
        let sessionID: UUID
        let text: String?
        var actionConsumed = false
        var saveAttempt: UUID?
        var cancelSave: (@MainActor () -> Void)?
        init(sessionID: UUID, text: String?) { self.sessionID = sessionID; self.text = text }
    }

    private(set) var window: NSWindow?
    private let title: String
    private let onAction: (Action) -> Void
    private let textActions: TextActions
    private let presentsWindows: Bool
    private let announce: @MainActor (String) -> Void
    private var sessionID: UUID?
    private var sessionFinished = false
    private var presentation: Presentation?
    private var consumingButtons: [NSButton] = []
    private var saveButton: NSButton?
    private var status: NSTextField?

    convenience init(title: String = "QRSnap", onAction: @escaping (Action) -> Void) {
        self.init(title: title, textActions: .native, presentsWindows: true, onAction: onAction)
    }

    init(title: String = "QRSnap", textActions: TextActions, presentsWindows: Bool = true,
         announce: @escaping @MainActor (String) -> Void = AccessibilityAnnouncements.post,
         onAction: @escaping (Action) -> Void) {
        self.title = title
        self.textActions = textActions
        self.presentsWindows = presentsWindows
        self.announce = announce
        self.onAction = onAction
        super.init()
    }

    /// A selecting event establishes the session; late events from older sessions are ignored.
    func receive(_ event: ScanWorkflow.Event) {
        switch event {
        case .selecting(let token):
            sessionID = token
            sessionFinished = false
            clearPresentation()
        case .processing, .progress:
            break
        case .choose(let token, let items):
            guard sessionID == token, !sessionFinished else { return }
            showChoices(items, token: token)
        case .actionRequired(let request):
            guard sessionID == request.sessionID, !sessionFinished else { return }
            showRequest(request)
        case .finished(let token, let outcome):
            guard sessionID == token, !sessionFinished else { return }
            sessionFinished = true
            switch outcome {
            case .cancelled, .handoffSucceeded:
                dismiss()
            case .failed(let failure, let text, let documentURL):
                showFailure(failure, text: text, documentURL: documentURL, token: token)
            }
        }
    }

    /// Programmatic dismissal never sends a cancellation action to the host.
    func dismiss() {
        sessionID = nil
        sessionFinished = true
        clearPresentation()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window,
              let current = presentation else { return }
        cancel(current.id, closeWindow: false)
    }

    private func showChoices(_ items: [DecodedItem], token: UUID) {
        guard let current = beginPresentation(token: token, text: nil, terminal: false) else { return }
        var rows: [NSView] = []
        for (index, item) in items.enumerated() {
            let preview: String
            if let payload = item.payload {
                // Flatten only the bounded preview; Copy/Save retain the untouched original.
                let excerpt = payload.prefix(160).split(whereSeparator: \.isWhitespace).joined(separator: " ")
                preview = payload.isEmpty ? "Empty text" : (excerpt.isEmpty ? "Whitespace text" : excerpt) + (payload.count > 160 ? "…" : "")
            } else { preview = "Unsupported: no text payload" }
            let label = makeLabel("QR \(index + 1): \(preview)", id: "result-choice-label-\(item.id)")
            let choose = button("Choose", id: "result-choose-\(item.id)", label: "Choose QR code \(index + 1): \(preview)") { [weak self] in
                self?.send(.choose(sessionID: token, observationID: item.id), presentationID: current.id)
            }
            consumingButtons.append(choose)
            let row = NSStackView(views: [label, choose])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            choose.setContentHuggingPriority(.required, for: .horizontal)
            rows.append(row)
        }
        let scroll = choiceScroll(rows)
        let cancel = cancelButton(current)
        show(current, heading: "Choose a QR code", detail: "Choose one result to continue. Tab moves between results; Space chooses the focused result. Each detected code is listed separately.",
             body: scroll, buttons: [cancel], initialFocus: cancel)
    }

    private func showRequest(_ request: ScanWorkflow.ActionRequest) {
        guard let current = beginPresentation(token: request.sessionID, text: request.observation.payload, terminal: false) else { return }
        let heading: String, detail: String, displayedText: String
        var buttons: [NSButton] = []
        switch request.kind {
        case .confirmExternal(let url, let handler):
            heading = "Open this destination?"
            detail = "The destination below will open in \(handler.name)."
            displayedText = url.absoluteString
            let open = button("Open", id: "result-open", label: "Open destination in \(handler.name)") { [weak self] in
                self?.send(.confirm(requestID: request.id), presentationID: current.id)
            }
            // No Return shortcut: opening an external destination requires selecting its action.
            consumingButtons.append(open)
            buttons.append(open)
        case .openBlockedAsText:
            heading = "Read this QR code as text"
            detail = "This type of destination is not opened directly. You can copy or save its text, or open a text document."
            displayedText = request.observation.payload ?? ""
        }
        if current.text != nil {
            let asText = button("Open as text", id: "result-open-as-text") { [weak self] in
                self?.send(.openAsText(requestID: request.id), presentationID: current.id)
            }
            consumingButtons.append(asText)
            buttons.append(asText)
            buttons += textButtons(current)
        }
        buttons.append(cancelButton(current))
        show(current, heading: heading, detail: detail, body: textView(displayedText), buttons: buttons,
             note: "Text documents opened by QRSnap are kept until you remove them.")
    }

    private func showFailure(_ failure: ScanFailure, text: String?, documentURL: URL?, token: UUID) {
        guard let current = beginPresentation(token: token, text: text, terminal: true) else { return }
        let message = failureMessage(failure)
        let retry = button("Retry", id: "result-retry") { [weak self] in
            guard let self, self.isCurrent(current.id) else { return }
            self.dismiss()
            self.onAction(.retry(sessionID: token))
        }
        consumingButtons.append(retry)
        var buttons = [retry]
        if text != nil { buttons += textButtons(current) }
        buttons.append(cancelButton(current))
        show(current, heading: message.0, detail: message.1, body: text.map(textView), buttons: buttons,
             note: documentURL == nil ? nil : "The text document already created is retained until you remove it.")
    }

    private func beginPresentation(token: UUID, text: String?, terminal: Bool) -> Presentation? {
        clearPresentation()
        // Cancelling a native save sheet can reenter the host; never replace a newer session.
        guard sessionID == token, sessionFinished == terminal else { return nil }
        let current = Presentation(sessionID: token, text: text)
        presentation = current
        return current
    }

    private func show(_ current: Presentation, heading: String, detail: String, body: NSView?,
                      buttons: [NSButton], note: String? = nil, initialFocus: NSView? = nil) {
        guard isCurrent(current.id) else { return }
        let result = ScanResultWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: body == nil ? 270 : 510),
                                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        result.title = "\(title) — \(heading)"
        result.minSize = NSSize(width: 650, height: body == nil ? 250 : 450)
        result.isReleasedWhenClosed = false
        result.delegate = self
        result.onEscape = { [weak self] in self?.cancel(current.id) }
        let headingLabel = makeLabel(heading, id: "result-heading")
        headingLabel.font = .systemFont(ofSize: 21, weight: .semibold)
        let detailLabel = makeLabel(detail, id: "result-detail")
        var views: [NSView] = [headingLabel, detailLabel]
        if let body { views.append(body) }
        if let note {
            let label = makeLabel(note, id: "result-retention")
            label.textColor = .secondaryLabelColor
            views.append(label)
        }
        let statusLabel = makeLabel("", id: "result-status")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setAccessibilityLabel("Result status")
        views.append(statusLabel)
        let actions = NSStackView(views: buttons)
        actions.orientation = .horizontal
        actions.spacing = 8
        views.append(actions)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24)
        ])
        for view in views where view !== actions { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        if let body { body.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true }
        result.contentView = content
        window = result
        status = statusLabel
        var focusOrder: [NSView] = consumingButtons
        if let text = (body as? NSScrollView)?.documentView as? NSTextView { focusOrder.append(text) }
        focusOrder.append(contentsOf: buttons)
        KeyboardFocusLoop.install(in: result, views: focusOrder)
        // Start a chooser on its payload-free Cancel control. Tab then reaches
        // the first result; its preview is exposed after explicit navigation.
        let focus = initialFocus ?? consumingButtons.first ?? buttons.first
        result.initialFirstResponder = focus
        if presentsWindows {
            result.center()
            NSApp.activate(ignoringOtherApps: true)
            result.makeKeyAndOrderFront(nil)
            if let focus { result.makeFirstResponder(focus) }
        }
        // Announce the interface state. The payload is available through its
        // labelled text view or the bounded preview of a deliberately focused row.
        announce(heading)
    }

    private func send(_ action: Action, presentationID: UUID) {
        guard let current = presentation, current.id == presentationID, !current.actionConsumed else { return }
        current.actionConsumed = true
        consumingButtons.forEach { $0.isEnabled = false }
        updateStatus("Working…", for: presentationID)
        guard isCurrent(presentationID) else { return }
        onAction(action)
    }

    private func cancel(_ id: UUID, closeWindow: Bool = true) {
        guard let current = presentation, current.id == id else { return }
        let token = current.sessionID
        sessionID = nil
        sessionFinished = true
        clearPresentation(closeWindow: closeWindow)
        onAction(.cancel(sessionID: token))
    }

    private func textButtons(_ current: Presentation) -> [NSButton] {
        let copy = button("Copy", id: "result-copy", key: "c", modifiers: .command) { [weak self] in
            guard let self, self.isCurrent(current.id), let text = self.presentation?.text else { return }
            let copied = self.textActions.copy(text)
            self.updateStatus(copied ? "Copied." : "The text could not be copied. Try again.", for: current.id)
        }
        let save = button("Save…", id: "result-save", key: "s", modifiers: .command) { [weak self] in
            self?.save(current.id)
        }
        saveButton = save
        return [copy, save]
    }

    private func save(_ id: UUID) {
        guard let current = presentation, current.id == id, current.saveAttempt == nil,
              let text = current.text, let window else { return }
        let attempt = UUID()
        current.saveAttempt = attempt
        saveButton?.isEnabled = false
        updateStatus("Choose where to save the text.", for: id)
        guard isCurrent(id), current.saveAttempt == attempt else { return }
        let cancelDialog = textActions.chooseSaveURL(window) { [weak self] url in
            guard let self, let active = self.presentation, active.id == id, active.saveAttempt == attempt else { return }
            active.saveAttempt = nil
            active.cancelSave = nil
            self.saveButton?.isEnabled = true
            guard let url else { self.updateStatus("Save cancelled.", for: id); return }
            // No suspension or user callback between this check and the native atomic write.
            guard self.isCurrent(id) else { return }
            do {
                try self.textActions.write(text, url)
                self.updateStatus("Saved.", for: id)
            } catch {
                self.updateStatus("The text could not be saved. Choose another location or try again.", for: id)
            }
        }
        if isCurrent(id), current.saveAttempt == attempt { current.cancelSave = cancelDialog }
        else if !isCurrent(id) { cancelDialog() }
    }

    private func clearPresentation(closeWindow: Bool = true) {
        let previous = presentation, previousWindow = window
        presentation = nil
        window = nil
        status = nil
        saveButton = nil
        consumingButtons = []
        previousWindow?.delegate = nil
        (previousWindow as? ScanResultWindow)?.onEscape = nil
        let cancelSave = previous?.cancelSave
        previous?.cancelSave = nil
        previous?.saveAttempt = nil
        cancelSave?()
        previousWindow?.contentView = nil
        if closeWindow { previousWindow?.close() }
    }

    private func isCurrent(_ id: UUID) -> Bool { presentation?.id == id }

    private func updateStatus(_ message: String, for id: UUID) {
        guard isCurrent(id), let status else { return }
        status.stringValue = message
        NSAccessibility.post(element: status, notification: .valueChanged)
        announce(message)
    }

    private func cancelButton(_ current: Presentation) -> NSButton {
        button("Cancel", id: "result-cancel", key: "\u{1b}") { [weak self] in self?.cancel(current.id) }
    }

    private func button(_ title: String, id: String, label: String? = nil, key: String = "",
                        modifiers: NSEvent.ModifierFlags = [], action: @escaping () -> Void) -> NSButton {
        let button = ScanResultButton(title: title, invoke: action)
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.setAccessibilityIdentifier(id)
        button.setAccessibilityLabel(label ?? title)
        button.keyEquivalent = key
        button.keyEquivalentModifierMask = modifiers
        return button
    }

    private func makeLabel(_ text: String, id: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.identifier = NSUserInterfaceItemIdentifier(id)
        label.setAccessibilityIdentifier(id)
        return label
    }

    private func textView(_ text: String) -> NSView {
        let view = ScanResultTextView(frame: NSRect(x: 0, y: 0, width: 650, height: 230))
        view.identifier = NSUserInterfaceItemIdentifier("result-text")
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.font = .systemFont(ofSize: 14)
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.string = text
        view.setAccessibilityLabel("Decoded text or destination")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.documentView = view
        return scroll
    }

    private func choiceScroll(_ rows: [NSView]) -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        let document = ScanResultDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12)
        ])
        rows.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return scroll
    }

    private func failureMessage(_ failure: ScanFailure) -> (String, String) {
        switch failure {
        case .noQR: return ("No QR code found", "Select the whole QR code, including its border, then try again.")
        case .unsupportedPayload: return ("Unsupported QR payload", "This QR code has no supported text payload, or its text exceeds the supported size.")
        case .permissionUnavailable: return ("Screen access unavailable", "Check screen access in System Settings. You may need to quit and reopen QRSnap before retrying.")
        case .displayChanged: return ("The display arrangement changed", "Start a new selection on a connected display.")
        case .invalidSelection, .selectionTooSmall: return ("Select a larger area", "Select at least 12 × 12 points and include the whole QR code and its border.")
        case .regionTooLarge: return ("Select a smaller area", "The selected region exceeds the capture size limit.")
        case .timedOut: return ("The scan took too long", "Try selecting a smaller area, then retry.")
        case .captureFailed: return ("The screen could not be captured", "Check screen access and the display arrangement, then retry.")
        case .decodeFailed: return ("The image could not be read", "Try selecting the whole QR code again.")
        case .handlerUnavailable: return ("No application is available", "The default application could not be found. You can copy or save any retained text below.")
        case .fileWriteFailed: return ("The text document could not be created", "Your decoded text is retained below. Copy it or save it to a location you choose.")
        case .launchFailed: return ("The destination could not be opened", "You can copy or save any retained text below, or retry the scan.")
        }
    }
}

@MainActor private final class ScanResultButton: KeyboardAccessibleButton {
    private let invoke: () -> Void
    init(title: String, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        action = #selector(pressed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func pressed() { if isEnabled { invoke() } }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        // Result actions have no default Return activation, including a focused
        // external Open button. Space or the native accessibility action is explicit.
        if (event.keyCode == 36 || event.keyCode == 76), modifiers.isEmpty { return }
        super.keyDown(with: event)
    }
}

@MainActor private final class ScanResultWindow: NSWindow {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if attachedSheet == nil, sheetParent == nil, modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor private final class ScanResultTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48, modifiers.isEmpty || modifiers == .shift {
            if modifiers == .shift { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor private final class ScanResultDocumentView: NSView {
    override var isFlipped: Bool { true }
}
