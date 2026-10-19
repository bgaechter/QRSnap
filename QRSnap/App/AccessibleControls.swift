import AppKit

/// These controls remain reachable when macOS's optional keyboard-navigation
/// preference is off. Modified keys remain available to AppKit and VoiceOver.
@MainActor class KeyboardAccessibleButton: NSButton {
    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool {
        // NSView's default also consults optional full keyboard access. This
        // application's explicit action loop must not depend on that preference.
        acceptsFirstResponder && !isHiddenOrHasHiddenAncestor && window?.canBecomeKey == true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds) }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48, modifiers.isEmpty || modifiers == .shift {
            if modifiers == .shift { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        } else if event.keyCode == 49, modifiers.isEmpty {
            // Holding Space must not repeat a side effect such as Copy or Save.
            if isEnabled, !event.isARepeat { performClick(nil) }
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor enum KeyboardFocusLoop {
    static func install(in window: NSWindow, views: [NSView]) {
        var seen = Set<ObjectIdentifier>()
        let ordered = views.filter { seen.insert(ObjectIdentifier($0)).inserted }
        guard let first = ordered.first else { return }
        window.autorecalculatesKeyViewLoop = false
        for (index, view) in ordered.enumerated() {
            view.nextKeyView = ordered[(index + 1) % ordered.count]
        }
        window.initialFirstResponder = first
    }
}

@MainActor enum AccessibilityAnnouncements {
    /// Presentation windows announce their own headings. Processing is announced
    /// only after the existing delayed-progress event, avoiding speech for quick scans.
    static func scanMessage(for event: ScanWorkflow.Event) -> String? {
        switch event {
        case .selecting: return "Select the whole QR code, including its border. Escape cancels."
        case .progress(_, true): return "Reading the selected area…"
        case .finished(_, .cancelled): return "Scan cancelled. Ready to scan again."
        case .finished(_, .handoffSucceeded): return "Sent to your default application."
        case .processing, .progress(_, false), .choose, .actionRequired, .finished(_, .failed): return nil
        }
    }

    /// Use the application element: the onboarding window is hidden during a scan.
    /// Callers pass interface status only, never decoded destinations or text.
    static func post(_ message: String) {
        guard !message.isEmpty else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
