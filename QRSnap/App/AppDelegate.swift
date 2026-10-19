import AppKit

/// Menu-bar entry point for the scan-to-default-application workflow.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = SelectionOverlay()
    private let permission = ScreenPermissionService()
    private let shortcutSettings = ShortcutSettingsController()
    private lazy var settingsWindow = SettingsWindowController(settings: shortcutSettings)
    private var mainWindow: NSWindow?
    private var statusLabel: NSTextField?
    private var shortcutLabel: NSTextField?
    private var permissionPromptOpen = false
    private var progressPanel: ScanProgressPanel?

    private lazy var scanner = ScanApplicationController(
        permission: permission,
        capture: ScreenCaptureService(),
        decoder: QRDecoder(),
        textStore: TextDocumentStore(directory: textDirectory),
        makeLauncher: { WorkspacePayloadLauncher(isCurrent: $0) },
        selection: .init(show: { [weak self] token, completion, cancel, displayChanged in
            guard let self else { return }
            self.overlay.cancelRequested = cancel
            self.overlay.displayChanged = displayChanged
            self.overlay.show(sessionID: token, completion: completion)
        }, close: { [weak self] in
            self?.overlay.close()
            self?.overlay.cancelRequested = nil
            self?.overlay.displayChanged = nil
        }),
        showPermissionExplanation: { [weak self] in self?.explainScreenPermission() },
        beforeSelection: { [weak self] in
            self?.mainWindow?.orderOut(nil)
            self?.settingsWindow.close()
        },
        onProgress: { [weak self] visible in
            self?.statusItem.button?.title = visible ? "Reading…" : ""
        },
        onProcessingUI: { [weak self] visible in self?.showProcessingUI(visible) },
        onEvent: { [weak self] event in self?.receive(event) }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "qrcode.viewfinder", accessibilityDescription: "QRSnap")
        statusItem.button?.toolTip = "QRSnap — scan a QR code from your screen"
        let menu = NSMenu()
        add("Scan QR code…", #selector(scan), to: menu)
        add("Cancel current scan", #selector(cancelScan), to: menu)
        menu.addItem(.separator())
        add("Open QRSnap…", #selector(showMainWindow), to: menu)
        add("Settings…", #selector(showSettings), to: menu)
        add("Screen access…", #selector(explainScreenPermission), to: menu)
        add("Show scanned text files…", #selector(showTextFiles), to: menu)
        menu.addItem(.separator())
        add("About QRSnap…", #selector(about), to: menu)
        add("Quit QRSnap", #selector(quit), to: menu)
        statusItem.menu = menu
        shortcutSettings.onInvoke = { [weak self] in self?.scan() }
        settingsWindow.onApply = { [weak self] _ in self?.refreshShortcutLabel() }
        // XCTest loads this app as a host. It must not restore a user's hotkey or
        // show onboarding; tests inject their own registration/capture/launch effects.
        guard !Self.isTestHost else { return }
        shortcutSettings.restore()
        showMainWindow()
    }

    private static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        NSClassFromString("XCTestCase") != nil || NSClassFromString("XCTest.XCTestCase") != nil
    }

    @objc private func showMainWindow() {
        if let mainWindow {
            refreshShortcutLabel()
            NSApp.activate(ignoringOtherApps: true)
            mainWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "QRSnap"
        window.minSize = NSSize(width: 560, height: 540)
        window.isReleasedWhenClosed = false
        let title = NSTextField(wrappingLabelWithString: "Read a QR code from your screen")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "Choose Scan, then drag around a QR code in another app. Include its border. Press Escape to cancel.")
        let policy = NSTextField(wrappingLabelWithString: "Web links open in your default browser. Text opens in your default text app. Other app links ask for confirmation, and multiple codes let you choose one.")
        let privacy = NSTextField(wrappingLabelWithString: "Screen images stay in memory. Text documents opened by QRSnap are kept until you remove them. Copy and Save happen only when you choose them.")
        privacy.textColor = .secondaryLabelColor
        let scan = NSButton(title: "Scan QR code…", target: self, action: #selector(scan))
        scan.bezelStyle = .rounded
        scan.keyEquivalent = "\r"
        let settings = NSButton(title: "Settings…", target: self, action: #selector(showSettings))
        settings.bezelStyle = .rounded
        let files = NSButton(title: "Show scanned text files…", target: self, action: #selector(showTextFiles))
        files.bezelStyle = .rounded
        let actions = NSStackView(views: [scan, settings, files])
        actions.orientation = .horizontal
        actions.spacing = 8
        let shortcut = NSTextField(wrappingLabelWithString: "")
        shortcutLabel = shortcut
        let status = NSTextField(wrappingLabelWithString: "Ready to scan. Screen access is requested only when you continue.")
        status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel("Scan status")
        statusLabel = status
        let stack = NSStackView(views: [title, detail, policy, actions, shortcut, privacy, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])
        for label in [title, detail, policy, privacy, shortcut, status] {
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        window.contentView = content
        mainWindow = window
        refreshShortcutLabel()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    @objc private func scan() {
        guard !permissionPromptOpen else { return }
        _ = scanner.startScan()
    }

    @objc private func cancelScan() { scanner.cancel() }

    @objc private func showSettings() {
        // Do not put settings over a live selection or consume its Escape key.
        scanner.cancel()
        settingsWindow.show()
    }

    @objc private func explainScreenPermission() {
        guard !permissionPromptOpen else { return }
        scanner.cancel()
        permissionPromptOpen = true
        defer { permissionPromptOpen = false }
        let prompt = NSAlert()
        prompt.messageText = permission.isGranted ? "Screen access is enabled" : "Allow screen access to scan a QR code"
        prompt.informativeText = "QRSnap reads only the area you select, on demand. It does not save screen images or record continuously. Manage access in System Settings → Privacy & Security → Screen & System Audio Recording. After changing access, you may need to quit and reopen this exact app, then choose Scan again."
        if permission.isGranted {
            prompt.addButton(withTitle: "OK")
        } else {
            prompt.addButton(withTitle: "Continue to macOS permission")
            prompt.addButton(withTitle: "Cancel")
        }
        NSApp.activate(ignoringOtherApps: true)
        let grantedBeforePrompt = permission.isGranted
        if prompt.runModal() == .alertFirstButtonReturn, !grantedBeforePrompt {
            _ = permission.request()
            statusLabel?.stringValue = "Review screen access in System Settings, then choose Scan again. A relaunch may be required."
        }
    }

    private func receive(_ event: ScanWorkflow.Event) {
        let message: String
        switch event {
        case .selecting: message = "Drag around a QR code. Escape cancels."
        case .processing: message = "Reading the selected area…"
        case .progress: return
        case .choose: message = "Choose one of the detected QR codes."
        case .actionRequired: message = "Review the destination or choose a text action."
        case .finished(_, .handoffSucceeded): message = "Sent to your default application."
        case .finished(_, .cancelled): message = "Scan cancelled. Ready to scan again."
        case .finished(_, .failed): message = "The scan could not finish. Review the recovery window or try again."
        }
        statusLabel?.stringValue = message
        if let statusLabel { NSAccessibility.post(element: statusLabel, notification: .valueChanged) }
    }

    private func refreshShortcutLabel() {
        shortcutLabel?.stringValue = shortcutSettings.status.message
    }

    private func showProcessingUI(_ visible: Bool) {
        if !visible {
            progressPanel?.onCancel = nil
            progressPanel?.close()
            progressPanel = nil
            return
        }
        guard progressPanel == nil, let token = scanner.sessionID else { return }
        let panel = ScanProgressPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
                                      styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "QRSnap"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in
            guard let self, self.scanner.sessionID == token else { return }
            self.scanner.cancel()
        }
        let label = NSTextField(labelWithString: "Reading the selected area…")
        let cancel = NSButton(title: "Cancel", target: panel, action: #selector(ScanProgressPanel.cancelPressed))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [label, cancel])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        panel.contentView = content
        panel.center()
        progressPanel = panel
        // Take key focus before selection panels close, then retain cancellation
        // through decoding and handoff. Delayed progress is a separate status label.
        panel.makeKeyAndOrderFront(nil)
    }

    private var textDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.benny.QRSnap", isDirectory: true)
            .appendingPathComponent("Scanned Text", isDirectory: true)
    }

    @objc private func showTextFiles() {
        do {
            try FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            NSWorkspace.shared.activateFileViewerSelecting([textDirectory])
        } catch { message("Folder unavailable", "The scanned-text folder could not be opened.") }
    }

    @objc private func about() {
        message("QRSnap", "Select a QR code on your screen and open its contents with your default application. Requires macOS 14 or later.\n\nScreen images remain in memory; opened text documents stay until you remove them. No analytics or app-originated network requests. Drag selection requires a pointer.\n\nMIT License · QRSnap contributors")
    }

    private func message(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func add(_ title: String, _ selector: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        scanner.cancel()
        settingsWindow.close()
        shortcutSettings.terminate()
        overlay.close()
    }
}

@MainActor private final class ScanProgressPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    @objc func cancelPressed() { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
