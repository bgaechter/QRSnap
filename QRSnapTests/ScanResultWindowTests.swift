#if !STANDALONE_TESTS && !SWIFT_PACKAGE
import AppKit
import XCTest
@testable import QRSnap

/// Hosted AppKit tests inspect real, hidden controls. No pasteboard, save panel, file, or app launch is used.
@MainActor final class ScanResultWindowTests: XCTestCase {
    func testChooserKeepsDuplicateNilAndEmptyObservationsAndCapsPreviews() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let session = UUID()
        controller.receive(.selecting(session))
        controller.receive(.choose(session, [item(1, "same"), item(2, "same"), item(3, nil), item(4, ""),
                                             item(5, String(repeating: "\n", count: 200))]))
        for id in 1...5 { XCTAssertNotNil(find("result-choose-\(id)", in: controller)) }
        XCTAssertTrue(try label("result-choice-label-3", in: controller).stringValue.contains("Unsupported"))
        XCTAssertTrue(try label("result-choice-label-4", in: controller).stringValue.contains("Empty text"))
        let preview = try label("result-choice-label-5", in: controller).stringValue
        XCTAssertFalse(preview.contains("\n"))
        XCTAssertLessThan(preview.count, 180)
        let first = try button("result-choose-1", in: controller)
        let second = try button("result-choose-2", in: controller)
        second.performClick(nil)
        first.performClick(nil)
        second.performClick(nil)
        XCTAssertEqual(effects.actions, [.choose(sessionID: session, observationID: 2)])
        XCTAssertFalse(first.isEnabled)
        XCTAssertFalse(second.isEnabled)
    }

    func testConfirmationShowsDestinationAndHandlerAndConsumesCompetingActions() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let session = UUID(), old = request(session: UUID(), text: "ignored", external: true)
        controller.receive(.selecting(session))
        controller.receive(.actionRequired(old))
        XCTAssertNil(controller.window)
        let current = request(session: session, text: " example:hello \n", external: true)
        controller.receive(.actionRequired(current))
        XCTAssertEqual(try text(in: controller).string, "example:hello")
        XCTAssertTrue(try label("result-detail", in: controller).stringValue.contains("Example Reader"))
        let open = try button("result-open", in: controller)
        let asText = try button("result-open-as-text", in: controller)
        XCTAssertEqual(open.keyEquivalent, "")
        open.performClick(nil)
        asText.performClick(nil)
        open.performClick(nil)
        XCTAssertEqual(effects.actions, [.confirm(requestID: current.id)])
        XCTAssertFalse(open.isEnabled)
        XCTAssertFalse(asText.isEnabled)
    }

    func testReplacementRequestRejectsOldControlsAndAllowsTextFallback() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let session = UUID() // Replacement requests share a session but have different identities.
        controller.receive(.selecting(session))
        let oldRequest = request(session: session, text: "example:hello", external: true)
        controller.receive(.actionRequired(oldRequest))
        let oldOpen = try button("result-open", in: controller)
        let oldCopy = try button("result-copy", in: controller)
        let replacement = request(session: session, text: "file:///harmless-example")
        controller.receive(.actionRequired(replacement))
        oldOpen.performClick(nil)
        oldCopy.performClick(nil)
        XCTAssertTrue(effects.actions.isEmpty)
        XCTAssertTrue(effects.copies.isEmpty)
        XCTAssertNil(find("result-open", in: controller))
        try button("result-copy", in: controller).performClick(nil)
        try button("result-open-as-text", in: controller).performClick(nil)
        XCTAssertEqual(effects.copies, ["file:///harmless-example"])
        XCTAssertEqual(effects.actions, [.openAsText(requestID: replacement.id)])
    }

    func testCopyPreservesEmptyUnicodeAndWhitespaceAndCanRecoverFromFailure() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        for original in ["", "  e\u{301} 🧭\n\t尾\r\n"] {
            let session = UUID()
            controller.receive(.selecting(session))
            controller.receive(.finished(session, .failed(.launchFailed, retainedText: original, documentURL: nil)))
            let copy = try button("result-copy", in: controller)
            effects.copySucceeds = false
            copy.performClick(nil)
            XCTAssertTrue(try label("result-status", in: controller).stringValue.contains("could not be copied"))
            effects.copySucceeds = true
            copy.performClick(nil)
            XCTAssertEqual(Array(effects.copies.suffix(2)), [original, original])
            XCTAssertEqual(Array(try text(in: controller).string.utf8), Array(original.utf8))
            XCTAssertEqual(try label("result-status", in: controller).stringValue, "Copied.")
            XCTAssertEqual(copy.keyEquivalent, "c")
            XCTAssertEqual(copy.keyEquivalentModifierMask, .command)
            XCTAssertFalse(try text(in: controller).isEditable)
            XCTAssertTrue(try text(in: controller).isSelectable)
        }
    }

    func testSavePreservesOriginalAndHandlesCancelFailureAndRetry() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let session = UUID(), original = " \t e\u{301} 🧭\n尾\r\n"
        controller.receive(.selecting(session))
        controller.receive(.actionRequired(request(session: session, text: original)))
        let save = try button("result-save", in: controller)
        save.performClick(nil)
        save.performClick(nil)
        XCTAssertEqual(effects.saveCompletions.count, 1)
        XCTAssertFalse(save.isEnabled)
        effects.saveCompletions[0](nil)
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(effects.writes.isEmpty)
        save.performClick(nil)
        effects.writeFails = true
        effects.saveCompletions[1](saveURL)
        XCTAssertTrue(try label("result-status", in: controller).stringValue.contains("could not be saved"))
        XCTAssertTrue(save.isEnabled)
        save.performClick(nil)
        effects.writeFails = false
        effects.saveCompletions[2](saveURL)
        effects.saveCompletions[2](saveURL)
        XCTAssertEqual(effects.writes.count, 2)
        XCTAssertEqual(effects.writes.map { Array($0.0.utf8) }, [Array(original.utf8), Array(original.utf8)])
        XCTAssertEqual(effects.writes.map(\.1), [saveURL, saveURL])
        XCTAssertEqual(try label("result-status", in: controller).stringValue, "Saved.")
    }

    func testPendingSaveIsCancelledAndCannotWriteAfterPresentationReplacement() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let first = UUID(), second = UUID()
        controller.receive(.selecting(first))
        controller.receive(.actionRequired(request(session: first, text: "old")))
        try button("result-save", in: controller).performClick(nil)
        controller.receive(.selecting(second))
        controller.receive(.actionRequired(request(session: second, text: "new")))
        let replacementWindow = controller.window
        effects.saveCompletions[0](saveURL)
        controller.receive(.finished(first, .handoffSucceeded))
        XCTAssertEqual(effects.cancelledSaves, 1)
        XCTAssertTrue(effects.writes.isEmpty)
        XCTAssertTrue(controller.window === replacementWindow)
        XCTAssertEqual(try label("result-status", in: controller).stringValue, "")
        try button("result-save", in: controller).performClick(nil)
        controller.dismiss()
        effects.saveCompletions[1](saveURL)
        XCTAssertEqual(effects.cancelledSaves, 2)
        XCTAssertTrue(effects.writes.isEmpty)
        XCTAssertTrue(effects.actions.isEmpty)
    }

    func testSynchronousSaveCompletionWritesEmptyTextOnce() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        effects.synchronousSaveURL = saveURL
        let session = UUID()
        controller.receive(.selecting(session))
        controller.receive(.finished(session, .failed(.fileWriteFailed, retainedText: "", documentURL: nil)))
        try button("result-save", in: controller).performClick(nil)
        XCTAssertEqual(effects.writes.count, 1)
        XCTAssertEqual(effects.writes.first?.0, "")
        XCTAssertEqual(effects.cancelledSaves, 0)
        XCTAssertTrue(try button("result-save", in: controller).isEnabled)
        XCTAssertEqual(try label("result-status", in: controller).stringValue, "Saved.")
    }

    func testTerminalRecoveryDistinguishesNilAndEmptyAndRetryIsReentrantSafe() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let first = UUID(), second = UUID()
        controller.receive(.selecting(first))
        controller.receive(.finished(first, .failed(.noQR, retainedText: nil, documentURL: nil)))
        XCTAssertEqual(try label("result-heading", in: controller).stringValue, "No QR code found")
        XCTAssertNil(find("result-copy", in: controller))
        XCTAssertNil(find("result-save", in: controller))
        let retry = try button("result-retry", in: controller)
        effects.onAction = { [weak controller] action in
            guard let controller else { return }
            guard case .retry = action else { return }
            XCTAssertNil(controller.window)
            controller.receive(.selecting(second))
            controller.receive(.finished(second, .failed(.unsupportedPayload, retainedText: "", documentURL: self.saveURL)))
        }
        retry.performClick(nil)
        retry.performClick(nil)
        XCTAssertEqual(effects.actions, [.retry(sessionID: first)])
        XCTAssertEqual(try label("result-heading", in: controller).stringValue, "Unsupported QR payload")
        XCTAssertNotNil(find("result-copy", in: controller))
        XCTAssertNotNil(find("result-save", in: controller))
        XCTAssertNotNil(find("result-retention", in: controller))
        controller.receive(.actionRequired(request(session: second, text: "late")))
        XCTAssertEqual(try text(in: controller).string, "")
    }

    func testEscapeAndWindowCloseCancelExactlyOnceAndDismissDoesNotCancel() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let first = UUID()
        controller.receive(.selecting(first))
        controller.receive(.actionRequired(request(session: first, text: "one")))
        let oldWindow = try XCTUnwrap(controller.window)
        let oldCancel = try button("result-cancel", in: controller)
        XCTAssertEqual(oldCancel.keyEquivalent, "\u{1b}")
        oldWindow.cancelOperation(nil)
        oldWindow.close()
        oldCancel.performClick(nil)
        XCTAssertEqual(effects.actions, [.cancel(sessionID: first)])
        let second = UUID()
        controller.receive(.selecting(second))
        controller.receive(.actionRequired(request(session: second, text: "two")))
        try XCTUnwrap(controller.window).close()
        XCTAssertEqual(effects.actions, [.cancel(sessionID: first), .cancel(sessionID: second)])
        let third = UUID()
        controller.receive(.selecting(third))
        controller.receive(.actionRequired(request(session: third, text: "three")))
        controller.dismiss()
        XCTAssertEqual(effects.actions.count, 2)
    }

    func testSideEffectReentrancyCannotOverwriteNewPresentationStatus() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let first = UUID(), second = UUID(), third = UUID()
        controller.receive(.selecting(first))
        controller.receive(.actionRequired(request(session: first, text: "one")))
        effects.onCopy = { [weak controller] in
            guard let controller else { return }
            controller.receive(.selecting(second))
            controller.receive(.actionRequired(self.request(session: second, text: "two")))
        }
        try button("result-copy", in: controller).performClick(nil)
        XCTAssertEqual(try label("result-status", in: controller).stringValue, "")
        effects.onWrite = { [weak controller] in
            guard let controller else { return }
            controller.receive(.selecting(third))
            controller.receive(.actionRequired(self.request(session: third, text: "three")))
        }
        try button("result-save", in: controller).performClick(nil)
        effects.saveCompletions[0](saveURL)
        XCTAssertEqual(try label("result-status", in: controller).stringValue, "")
        XCTAssertEqual(try text(in: controller).string, "three")
        XCTAssertTrue(effects.actions.isEmpty)
    }

    func testSuccessAndCancellationDismissAndIgnoreLateEvents() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        for outcome in [ScanWorkflow.Outcome.handoffSucceeded, .cancelled] {
            let session = UUID()
            controller.receive(.selecting(session))
            controller.receive(.actionRequired(request(session: session, text: "value")))
            controller.receive(.finished(session, outcome))
            controller.receive(.choose(session, [item(1, "late")]))
            controller.receive(.finished(session, .failed(.launchFailed, retainedText: "late", documentURL: nil)))
            XCTAssertNil(controller.window)
        }
        XCTAssertTrue(effects.actions.isEmpty)
    }

    func testKeyboardChooserTraversalAndSpaceChooseOnlyTheFocusedObservation() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let session = UUID()
        controller.receive(.selecting(session))
        controller.receive(.choose(session, [item(1, "first"), item(2, "second"), item(3, nil)]))
        let window = try XCTUnwrap(controller.window)
        let first = try button("result-choose-1", in: controller)
        let second = try button("result-choose-2", in: controller)
        XCTAssertTrue(window.initialFirstResponder === (try button("result-cancel", in: controller)))
        XCTAssertTrue(first.acceptsFirstResponder)
        XCTAssertTrue(first.canBecomeKeyView)
        XCTAssertTrue(window.makeFirstResponder(first))
        first.keyDown(with: key(48, "\t", window: window))
        XCTAssertTrue(window.firstResponder === second)
        second.keyDown(with: key(48, "\t", modifiers: .shift, window: window))
        XCTAssertTrue(window.firstResponder === first)
        first.keyDown(with: key(48, "\t", window: window))
        second.keyDown(with: key(49, " ", window: window))
        second.keyDown(with: key(49, " ", repeatKey: true, window: window))
        XCTAssertEqual(effects.actions, [.choose(sessionID: session, observationID: 2)])
        XCTAssertFalse(first.acceptsFirstResponder)
        XCTAssertFalse(first.canBecomeKeyView)
        second.keyDown(with: key(48, "\t", window: window))
        XCTAssertTrue(window.firstResponder === (try button("result-cancel", in: controller)))
        XCTAssertTrue(try XCTUnwrap(second.accessibilityLabel()).contains("second"))
    }

    func testKeyboardTextReviewCopyAndClosePreserveOriginalAndCancelOnce() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let session = UUID(), original = "  e\u{301} 🧭\n尾\r\n"
        controller.receive(.selecting(session))
        controller.receive(.actionRequired(request(session: session, text: original, external: true)))
        let window = try XCTUnwrap(controller.window)
        let open = try button("result-open", in: controller)
        XCTAssertEqual(open.keyEquivalent, "")
        XCTAssertNil(window.defaultButtonCell)
        XCTAssertTrue(window.makeFirstResponder(open))
        for code in [UInt16(36), UInt16(76)] {
            _ = window.performKeyEquivalent(with: key(code, "\r", window: window))
            open.keyDown(with: key(code, "\r", window: window))
        }
        XCTAssertTrue(effects.actions.isEmpty)
        let decoded = try text(in: controller)
        XCTAssertTrue(window.makeFirstResponder(decoded))
        XCTAssertTrue(decoded.performKeyEquivalent(with: key(0, "a", modifiers: .command, window: window)))
        XCTAssertEqual(decoded.selectedRange(), NSRange(location: 0, length: decoded.string.utf16.count))
        decoded.keyDown(with: key(48, "\t", window: window))
        let copy = try button("result-copy", in: controller)
        XCTAssertTrue(window.firstResponder === copy)
        copy.keyDown(with: key(49, " ", window: window))
        copy.keyDown(with: key(49, " ", repeatKey: true, window: window))
        XCTAssertEqual(effects.copies.map { Array($0.utf8) }, [Array(original.utf8)])
        XCTAssertTrue(effects.actions.isEmpty)
        XCTAssertTrue(window.performKeyEquivalent(with: key(13, "w", modifiers: .command, window: window)))
        window.close()
        XCTAssertEqual(effects.actions, [.cancel(sessionID: session)])
    }

    func testFocusedChoiceScrollsIntoViewAndIncludesItsBoundedPreview() throws {
        let (controller, _) = makeController()
        defer { controller.dismiss() }
        let session = UUID()
        controller.receive(.selecting(session))
        controller.receive(.choose(session, (1...30).map { item($0, "Synthetic result \($0)") }))
        let window = try XCTUnwrap(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        let last = try button("result-choose-30", in: controller)
        XCTAssertTrue(window.makeFirstResponder(last))
        let scroll = try XCTUnwrap(last.enclosingScrollView)
        let document = try XCTUnwrap(scroll.documentView)
        let focusedBounds = document.convert(last.bounds, from: last)
        XCTAssertTrue(document.visibleRect.intersects(focusedBounds))
        XCTAssertTrue(try XCTUnwrap(last.accessibilityLabel()).contains("Synthetic result 30"))
    }

    func testAnnouncementsDescribeStatusWithoutAutomaticallyReadingPayloads() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let session = UUID(), original = "file:///synthetic/private-text-雪"
        controller.receive(.selecting(session))
        controller.receive(.actionRequired(request(session: session, text: original)))
        XCTAssertEqual(effects.announcements, ["Read this QR code as text"])
        try button("result-copy", in: controller).performClick(nil)
        try button("result-save", in: controller).performClick(nil)
        effects.saveCompletions[0](nil)
        XCTAssertEqual(Array(effects.announcements.suffix(3)),
                       ["Copied.", "Choose where to save the text.", "Save cancelled."])
        XCTAssertFalse(effects.announcements.joined().contains(original))
        controller.dismiss()
        let count = effects.announcements.count
        controller.receive(.finished(session, .failed(.launchFailed, retainedText: original, documentURL: nil)))
        XCTAssertEqual(effects.announcements.count, count)
    }

    func testAnnouncementReentrancyCannotDispatchOrPresentSaveForObsoleteResult() throws {
        let (controller, effects) = makeController()
        defer { controller.dismiss() }
        let first = UUID(), second = UUID()
        controller.receive(.selecting(first))
        controller.receive(.actionRequired(request(session: first, text: "first", external: true)))
        effects.onAnnouncement = { [weak controller] message in
            guard message == "Working…" else { return }
            controller?.receive(.selecting(second))
            controller?.receive(.actionRequired(self.request(session: second, text: "second")))
        }
        try button("result-open", in: controller).performClick(nil)
        XCTAssertTrue(effects.actions.isEmpty)
        XCTAssertEqual(try text(in: controller).string, "second")
        effects.onAnnouncement = { [weak controller] message in
            if message == "Choose where to save the text." { controller?.dismiss() }
        }
        try button("result-save", in: controller).performClick(nil)
        XCTAssertTrue(effects.saveCompletions.isEmpty)
        XCTAssertTrue(effects.writes.isEmpty)
    }

    func testScanAnnouncementsUseDelayedProgressAndGenericTerminalStatus() {
        let token = UUID(), original = "https://example.com/synthetic-private-value"
        XCTAssertNotNil(AccessibilityAnnouncements.scanMessage(for: .selecting(token)))
        XCTAssertNil(AccessibilityAnnouncements.scanMessage(for: .processing(token)))
        XCTAssertNil(AccessibilityAnnouncements.scanMessage(for: .progress(token, isVisible: false)))
        XCTAssertNotNil(AccessibilityAnnouncements.scanMessage(for: .progress(token, isVisible: true)))
        XCTAssertNil(AccessibilityAnnouncements.scanMessage(for: .choose(token, [item(1, original)])))
        XCTAssertNil(AccessibilityAnnouncements.scanMessage(for: .actionRequired(request(session: token, text: original))))
        XCTAssertNil(AccessibilityAnnouncements.scanMessage(for: .finished(token, .failed(.launchFailed, retainedText: original, documentURL: nil))))
        XCTAssertTrue(AccessibilityAnnouncements.scanMessage(for: .finished(token, .cancelled))?.contains("cancelled") == true)
        XCTAssertEqual(AccessibilityAnnouncements.scanMessage(for: .finished(token, .handoffSucceeded)),
                       "Sent to your default application.")
    }

    private func key(_ code: UInt16, _ characters: String, modifiers: NSEvent.ModifierFlags = [],
                     repeatKey: Bool = false, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code)!
    }

    private let saveURL = URL(fileURLWithPath: "/not-written/Scanned Text.txt")
    private func item(_ id: Int, _ text: String?) -> DecodedItem { DecodedItem(id: id, payload: text, bounds: .zero) }

    private func request(session: UUID, text: String, external: Bool = false) -> ScanWorkflow.ActionRequest {
        let kind: ScanWorkflow.ActionRequest.Kind = external
            ? .confirmExternal(URL(string: "example:hello")!, HandlerMetadata(name: "Example Reader", applicationURL: URL(fileURLWithPath: "/Applications/Example.app")))
            : .openBlockedAsText
        return .init(id: UUID(), sessionID: session, observation: item(1, text), kind: kind)
    }

    private func makeController() -> (ScanResultWindowController, ResultWindowEffects) {
        _ = NSApplication.shared
        let effects = ResultWindowEffects()
        let controller = ScanResultWindowController(textActions: effects.boundaries, presentsWindows: false,
                                                   announce: { message in
            effects.announcements.append(message)
            effects.onAnnouncement?(message)
        }) {
            effects.actions.append($0)
            effects.onAction?($0)
        }
        return (controller, effects)
    }

    private func find(_ id: String, in controller: ScanResultWindowController) -> NSView? {
        func visit(_ view: NSView) -> NSView? {
            if view.identifier?.rawValue == id { return view }
            for child in view.subviews { if let match = visit(child) { return match } }
            return nil
        }
        return controller.window?.contentView.flatMap(visit)
    }
    private func button(_ id: String, in controller: ScanResultWindowController) throws -> NSButton {
        try XCTUnwrap(find(id, in: controller) as? NSButton)
    }
    private func label(_ id: String, in controller: ScanResultWindowController) throws -> NSTextField {
        try XCTUnwrap(find(id, in: controller) as? NSTextField)
    }
    private func text(in controller: ScanResultWindowController) throws -> NSTextView {
        try XCTUnwrap(find("result-text", in: controller) as? NSTextView)
    }
}

@MainActor private final class ResultWindowEffects {
    enum Failure: Error { case expected }
    var actions: [ScanResultWindowController.Action] = []
    var copies: [String] = []
    var writes: [(String, URL)] = []
    var saveCompletions: [@MainActor (URL?) -> Void] = []
    var cancelledSaves = 0
    var copySucceeds = true
    var writeFails = false
    var synchronousSaveURL: URL?
    var onAction: ((ScanResultWindowController.Action) -> Void)?
    var onCopy: (() -> Void)?
    var onWrite: (() -> Void)?
    var announcements: [String] = []
    var onAnnouncement: ((String) -> Void)?

    var boundaries: ScanResultWindowController.TextActions {
        .init(copy: { text in
            self.copies.append(text)
            self.onCopy?()
            return self.copySucceeds
        }, chooseSaveURL: { _, completion in
            self.saveCompletions.append(completion)
            if let url = self.synchronousSaveURL { completion(url) }
            return { self.cancelledSaves += 1 }
        }, write: { text, url in
            self.writes.append((text, url))
            self.onWrite?()
            if self.writeFails { throw Failure.expected }
        })
    }
}
#endif
