import AppKit
import Carbon

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Production recording still consumes local key events before menu equivalents.
    /// Tests inject this OS boundary without monitoring real keyboard input.
    struct RecordingMonitor {
        var install: @MainActor (NSWindow, @escaping @MainActor (UInt16, NSEvent.ModifierFlags, Bool) -> Void) -> (@MainActor () -> Void)?

        static var native: RecordingMonitor {
            RecordingMonitor { window, receive in
                guard window.isKeyWindow else { return nil }
                guard let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak window] event in
                    let keyCode = event.keyCode, flags = event.modifierFlags
                    let windowNumber = event.windowNumber, isRepeat = event.isARepeat
                    let consumed = MainActor.assumeIsolated {
                        guard let window, window.isKeyWindow, windowNumber == window.windowNumber else { return false }
                        receive(keyCode, flags, isRepeat)
                        return true
                    }
                    return consumed ? nil : event
                }) else { return nil }
                return { NSEvent.removeMonitor(monitor) }
            }
        }
    }

    private let settings: ShortcutSettingsController
    private let announce: @MainActor (String) -> Void
    private let recordingMonitor: RecordingMonitor
    private var draft: ShortcutPreferences
    private var stopKeyMonitor: (@MainActor () -> Void)?
    private var enabledButton: NSButton?
    private var shortcutLabel: NSTextField?
    private var statusLabel: NSTextField?
    private var recordButton: NSButton?
    private var defaultButton: NSButton?
    private var applyButton: NSButton?
    private(set) var window: NSWindow?
    var onApply: ((ShortcutRegistrationStatus) -> Void)?

    init(settings: ShortcutSettingsController,
         announce: @escaping @MainActor (String) -> Void = AccessibilityAnnouncements.post,
         recordingMonitor: RecordingMonitor = .native) {
        self.settings = settings
        self.announce = announce
        self.recordingMonitor = recordingMonitor
        draft = settings.preferences
        super.init()
    }

    /// Hidden presentation is used by hosted UI tests; it never installs a key monitor.
    func show(activate: Bool = true) {
        stopRecording()
        draft = settings.preferences
        if window == nil { buildWindow() }
        refresh()
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            if let enabledButton { window?.makeFirstResponder(enabledButton) }
        }
    }

    func close() {
        stopRecording(feedback: "Shortcut recording cancelled.", restoreFocus: false)
        window?.close()
    }

    private func buildWindow() {
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "QRSnap Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.onEscape = { [weak self] in
            guard let self else { return }
            if self.stopKeyMonitor != nil { self.stopRecording(feedback: "Shortcut recording cancelled.") }
            else { self.close() }
        }
        window.onClose = { [weak self] in self?.close() }
        let content = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
        let heading = NSTextField(labelWithString: "Scan shortcut")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(heading)
        let enabled = KeyboardAccessibleButton(title: "Enable global shortcut", target: self, action: #selector(changeEnabled))
        enabled.setButtonType(.switch)
        enabled.identifier = NSUserInterfaceItemIdentifier("settings-shortcut-enabled")
        enabled.setAccessibilityIdentifier("settings-shortcut-enabled")
        enabled.setAccessibilityLabel("Enable global shortcut")
        stack.addArrangedSubview(enabled)
        enabledButton = enabled

        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 19, weight: .medium)
        label.identifier = NSUserInterfaceItemIdentifier("settings-shortcut-value")
        label.setAccessibilityIdentifier("settings-shortcut-value")
        label.setAccessibilityLabel("Selected shortcut, US key position")
        shortcutLabel = label
        let record = button("Record shortcut…", action: #selector(toggleRecording), id: "settings-record")
        let reset = button("Use default", action: #selector(useDefault), id: "settings-default")
        recordButton = record
        defaultButton = reset
        let row = NSStackView(views: [label, record, reset])
        row.spacing = 12
        stack.addArrangedSubview(row)
        addText("Include Control, Option or Command. Shortcut names show US keyboard positions; the same physical key is used after you change keyboard layouts. Keyboard capture runs only while recording in this window.", to: stack)
        let status = addText("", to: stack)
        status.identifier = NSUserInterfaceItemIdentifier("settings-shortcut-status")
        status.setAccessibilityIdentifier("settings-shortcut-status")
        status.setAccessibilityLabel("Shortcut status")
        statusLabel = status
        let apply = button("Apply", action: #selector(applySettings), id: "settings-apply")
        apply.keyEquivalent = "\r"
        apply.keyEquivalentModifierMask = []
        applyButton = apply
        stack.addArrangedSubview(apply)

        let privacy = NSTextField(labelWithString: "Screen access and retained text")
        privacy.font = .systemFont(ofSize: 16, weight: .semibold)
        stack.addArrangedSubview(privacy)
        addText("Screen access is requested when you start a scan. QRSnap captures your selected region in memory; it does not save screenshot files. After changing screen access in System Settings → Privacy & Security, you may need to quit and reopen QRSnap.", to: stack)
        addText("Text opened as a document stays in QRSnap’s private Scanned Text folder until you remove it. Use Show scanned text files… from the menu to find it. Explicit Save… keeps a copy at the location you choose. Browsers and editors have their own history and retention policies.", to: stack)
        addText("QRSnap has no analytics or app-originated network requests. Drag selection requires a pointing device; it is not fully accessible to nonvisual users.", to: stack)
        window.contentView = content
        KeyboardFocusLoop.install(in: window, views: [enabled, record, reset, apply])
        window.center()
        self.window = window
    }

    @discardableResult private func addText(_ text: String, to stack: NSStackView) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return label
    }

    private func button(_ title: String, action: Selector, id: String) -> NSButton {
        let button = KeyboardAccessibleButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.setAccessibilityIdentifier(id)
        button.setAccessibilityLabel(title)
        return button
    }

    private func refresh() {
        enabledButton?.state = draft.enabled ? .on : .off
        shortcutLabel?.stringValue = draft.shortcut.displayName
        statusLabel?.stringValue = settings.status.message
        let recording = stopKeyMonitor != nil
        recordButton?.title = recording ? "Cancel recording" : "Record shortcut…"
        if let recordButton { recordButton.setAccessibilityLabel(recordButton.title) }
        enabledButton?.isEnabled = !recording
        defaultButton?.isEnabled = !recording
        applyButton?.isEnabled = !recording
    }

    @objc private func changeEnabled() {
        draft.enabled = enabledButton?.state == .on
        updateStatus("Apply to save your changes. " + settings.status.message)
    }

    @objc private func useDefault() {
        draft.shortcut = .defaultShortcut
        refresh()
        updateStatus("Default shortcut selected. Apply to save your changes.")
    }

    @objc private func applySettings() {
        guard stopKeyMonitor == nil else { return }
        let result = settings.apply(draft)
        refresh()
        updateStatus(result.message)
        onApply?(result)
    }

    @objc private func toggleRecording() {
        if stopKeyMonitor != nil { stopRecording(feedback: "Shortcut recording cancelled."); return }
        guard let window else { return }
        settings.beginRecording()
        stopKeyMonitor = recordingMonitor.install(window) { [weak self] keyCode, flags, isRepeat in
            self?.recordKey(keyCode: keyCode, flags: flags, isRepeat: isRepeat)
        }
        if stopKeyMonitor == nil { settings.endRecording() }
        refresh()
        onApply?(settings.status)
        if stopKeyMonitor != nil { updateStatus(settings.status.message) }
        else { updateStatus("Shortcut recording could not start. Activate Settings and try again. " + settings.status.message) }
    }

    private func recordKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool) {
        guard stopKeyMonitor != nil else { return }
        if keyCode == 53 { stopRecording(feedback: "Shortcut recording cancelled."); return }
        guard !isRepeat else { return }
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.command, cmdKey), (.shift, shiftKey)] {
            if flags.contains(flag) { modifiers |= UInt32(carbon) }
        }
        let shortcut = KeyboardShortcut(keyCode: UInt32(keyCode), modifiers: modifiers)
        if let message = shortcut.validationMessage {
            updateStatus(message + " Escape cancels.")
        } else {
            draft.shortcut = shortcut
            stopRecording()
            var message = "\(shortcut.displayName) selected. Apply to save your changes."
            if case .unavailable = settings.status { message += " " + settings.status.message }
            updateStatus(message)
        }
    }

    private func stopRecording(feedback: String? = nil, restoreFocus: Bool = true) {
        guard let stop = stopKeyMonitor else { return }
        stopKeyMonitor = nil
        stop()
        settings.endRecording()
        refresh()
        if restoreFocus, let recordButton { window?.makeFirstResponder(recordButton) }
        onApply?(settings.status)
        if let feedback { updateStatus(feedback + " " + settings.status.message) }
    }

    private func updateStatus(_ message: String) {
        statusLabel?.stringValue = message
        announce(message)
    }

    func windowDidResignKey(_ notification: Notification) {
        stopRecording(feedback: "Shortcut recording cancelled.", restoreFocus: false)
    }
    func windowWillClose(_ notification: Notification) {
        stopRecording(feedback: "Shortcut recording cancelled.", restoreFocus: false)
    }
}

@MainActor private final class SettingsWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onClose: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, !event.isARepeat {
            if event.keyCode == 53, modifiers.isEmpty { cancelOperation(nil); return true }
            if event.charactersIgnoringModifiers?.lowercased() == "w", modifiers == .command {
                onClose?()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
