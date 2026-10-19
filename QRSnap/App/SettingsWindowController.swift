import AppKit
import Carbon

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: ShortcutSettingsController
    private var draft: ShortcutPreferences
    private var eventMonitor: Any?
    private var enabledButton: NSButton?
    private var shortcutLabel: NSTextField?
    private var statusLabel: NSTextField?
    private var recordButton: NSButton?
    private var defaultButton: NSButton?
    private var applyButton: NSButton?
    private(set) var window: NSWindow?
    var onApply: ((ShortcutRegistrationStatus) -> Void)?

    init(settings: ShortcutSettingsController) {
        self.settings = settings
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
        }
    }

    func close() {
        stopRecording()
        window?.close()
    }

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "QRSnap Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
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
        let enabled = NSButton(checkboxWithTitle: "Enable global shortcut", target: self, action: #selector(changeEnabled))
        enabled.identifier = NSUserInterfaceItemIdentifier("settings-shortcut-enabled")
        stack.addArrangedSubview(enabled)
        enabledButton = enabled

        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 19, weight: .medium)
        label.identifier = NSUserInterfaceItemIdentifier("settings-shortcut-value")
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
        statusLabel = status
        let apply = button("Apply", action: #selector(applySettings), id: "settings-apply")
        applyButton = apply
        stack.addArrangedSubview(apply)

        let privacy = NSTextField(labelWithString: "Screen access and retained text")
        privacy.font = .systemFont(ofSize: 16, weight: .semibold)
        stack.addArrangedSubview(privacy)
        addText("Screen access is requested when you start a scan. QRSnap captures your selected region in memory; it does not save screenshot files. After changing screen access in System Settings → Privacy & Security, you may need to quit and reopen QRSnap.", to: stack)
        addText("Text opened as a document stays in QRSnap’s private Scanned Text folder until you remove it. Use Show scanned text files… from the menu to find it. Explicit Save… keeps a copy at the location you choose. Browsers and editors have their own history and retention policies.", to: stack)
        addText("QRSnap has no analytics or app-originated network requests. Drag selection requires a pointing device; it is not fully accessible to nonvisual users.", to: stack)
        window.contentView = content
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
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(id)
        return button
    }

    private func refresh() {
        enabledButton?.state = draft.enabled ? .on : .off
        shortcutLabel?.stringValue = draft.shortcut.displayName
        statusLabel?.stringValue = settings.status.message
        let recording = eventMonitor != nil
        recordButton?.title = recording ? "Cancel recording" : "Record shortcut…"
        enabledButton?.isEnabled = !recording
        defaultButton?.isEnabled = !recording
        applyButton?.isEnabled = !recording
    }

    @objc private func changeEnabled() {
        draft.enabled = enabledButton?.state == .on
        statusLabel?.stringValue = "Apply to save your changes. " + settings.status.message
    }

    @objc private func useDefault() {
        draft.shortcut = .defaultShortcut
        refresh()
        statusLabel?.stringValue = "Default shortcut selected. Apply to save your changes."
    }

    @objc private func applySettings() {
        stopRecording()
        let result = settings.apply(draft)
        refresh()
        statusLabel?.stringValue = result.message
        onApply?(result)
    }

    @objc private func toggleRecording() {
        if eventMonitor != nil { stopRecording(); return }
        guard window?.isKeyWindow == true else { return }
        settings.beginRecording()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let windowNumber = event.windowNumber
            let isRepeat = event.isARepeat
            let consumed = MainActor.assumeIsolated {
                guard let self, let window = self.window, window.isKeyWindow,
                      windowNumber == window.windowNumber else { return false }
                if keyCode == 53 { self.stopRecording(); return true }
                guard !isRepeat else { return true }
                var modifiers: UInt32 = 0
                for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.command, cmdKey), (.shift, shiftKey)] {
                    if flags.contains(flag) { modifiers |= UInt32(carbon) }
                }
                let shortcut = KeyboardShortcut(keyCode: UInt32(keyCode), modifiers: modifiers)
                if let message = shortcut.validationMessage {
                    self.statusLabel?.stringValue = message + " Escape cancels."
                } else {
                    self.draft.shortcut = shortcut
                    self.stopRecording()
                    self.statusLabel?.stringValue = "\(shortcut.displayName) selected. Apply to save your changes."
                }
                return true
            }
            return consumed ? nil : event
        }
        if eventMonitor == nil { settings.endRecording() }
        refresh()
        onApply?(settings.status)
    }

    private func stopRecording() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
        settings.endRecording()
        refresh()
        onApply?(settings.status)
    }

    func windowDidResignKey(_ notification: Notification) { stopRecording() }
    func windowWillClose(_ notification: Notification) { stopRecording() }
}
