import AppKit

/// Bounded A0 proof UI. Scans display evidence; production dispatch is gated on G0.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = SelectionOverlay()
    private let permission = ScreenPermissionService()
    private let capture = ScreenCaptureService()
    private let decoder = QRDecoder()
    private let shortcut = GlobalShortcut()
    private var session = SessionLifecycle()
    private var scanTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var reportWindow: NSWindow?
    private var controlsWindow: NSWindow?
    private var shortcutEnabled = false
    private var handoffBusy = false
    private var permissionCheckBusy = false
    private var shortcutButton: NSButton?
    private var shortcutMenuItem: NSMenuItem?
    private var resultPreview: SyntheticResultPreviewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "qrcode.viewfinder", accessibilityDescription: "QRSnap")
        let menu = NSMenu()
        add("Scan QR code…", #selector(scan), to: menu)
        add("Show test controls…", #selector(showControls), to: menu)
        add("Preview result workflow…", #selector(previewResults), to: menu)
        add("Diagnose screen access…", #selector(diagnoseScreenAccess), to: menu)
        add("Enable test shortcut (⌃⇧Q)", #selector(toggleShortcut(_:)), to: menu)
        shortcutMenuItem = menu.items.last
        add("Cancel current scan", #selector(cancel), to: menu)
        menu.addItem(.separator())
        add("Open synthetic text in default app…", #selector(testTextHandoff), to: menu)
        add("Show scanned text files…", #selector(showTextFiles), to: menu)
        add("About this feasibility build…", #selector(about), to: menu)
        menu.addItem(.separator())
        add("Quit QRSnap", #selector(quit), to: menu)
        statusItem.menu = menu
        shortcut.onInvoke = { [weak self] in self?.scan() }
        overlay.cancelRequested = { [weak self] in self?.cancel() }
        overlay.displayChanged = { [weak self] in self?.fail(.displayChanged) }
        showControls()
    }

    // A visible, keyboard-accessible entry point for the bounded feasibility build.
    // No permission, shortcut registration, or capture occurs merely by opening it.
    @objc private func showControls() {
        if let controlsWindow {
            NSApp.activate(ignoringOtherApps: true)
            controlsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "QRSnap — Feasibility checks"
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "Read a QR code from your screen")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "Open a synthetic QR image in another application, then choose Scan. Screen access is requested only after you continue. Captured images stay in memory; this proof displays results without opening QR destinations.")
        let scanButton = NSButton(title: "Scan QR code…", target: self, action: #selector(scan))
        scanButton.bezelStyle = .rounded
        scanButton.keyEquivalent = "\r"
        let textButton = NSButton(title: "Test default text application…", target: self, action: #selector(testTextHandoff))
        textButton.bezelStyle = .rounded
        let diagnosticButton = NSButton(title: "Diagnose screen access…", target: self, action: #selector(diagnoseScreenAccess))
        diagnosticButton.bezelStyle = .rounded
        let previewButton = NSButton(title: "Preview result workflow…", target: self, action: #selector(previewResults))
        previewButton.bezelStyle = .rounded
        let shortcutButton = NSButton(checkboxWithTitle: "Enable test shortcut (⌃⇧Q)", target: self, action: #selector(toggleShortcut(_:)))
        shortcutButton.state = shortcutEnabled ? .on : .off
        self.shortcutButton = shortcutButton
        let quitButton = NSButton(title: "Quit QRSnap", target: self, action: #selector(quit))
        quitButton.bezelStyle = .rounded
        let help = NSTextField(wrappingLabelWithString: "Control-Shift-Q can be enabled from the QR menu-bar icon. Text test documents are retained until you remove them; use Show scanned text files from the menu.")
        help.textColor = .secondaryLabelColor
        for view in [title, detail, scanButton, diagnosticButton, shortcutButton, textButton, previewButton, help, quitButton] { stack.addArrangedSubview(view) }
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        window.contentView = content
        window.center()
        controlsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls()
        return true
    }

    private func add(_ title: String, _ selector: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func scan() {
        guard session.phase == .idle, !permissionCheckBusy else { return }
        resultPreview?.dismiss()
        reportWindow?.close()
        guard permission.isGranted else {
            let prompt = NSAlert()
            prompt.messageText = "Allow screen access to scan a QR code"
            prompt.informativeText = "QRSnap reads the area you select on your screen. Images stay in memory and are not saved. macOS controls screen access; after changing permission you may need to quit and reopen QRSnap."
            prompt.addButton(withTitle: "Continue to macOS permission")
            prompt.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if prompt.runModal() == .alertFirstButtonReturn {
                _ = permission.request()
                message("Check screen access", "Review Screen & System Audio Recording in System Settings → Privacy & Security. Then invoke Scan again. If access still fails, quit and reopen QRSnap.")
            }
            return
        }
        controlsWindow?.orderOut(nil)
        guard let token = session.begin() else { return }
        overlay.show(sessionID: token) { [weak self] result in
            guard let self, self.session.contains(token) else { return }
            switch result {
            case .success(nil): self.cancel()
            case .failure(let failure): self.fail(failure)
            case .success(let selection?): self.runCapture(selection)
            }
        }
    }

    @objc private func diagnoseScreenAccess() {
        guard session.phase == .idle, !permissionCheckBusy else { return }
        let prompt = NSAlert()
        prompt.messageText = "Check screen access without capturing pixels"
        prompt.informativeText = "This asks ScreenCaptureKit whether shareable content is available and reports only permission status and a numeric error code. macOS may ask for screen permission. No window names or screen content are displayed or saved."
        prompt.addButton(withTitle: "Check access")
        prompt.addButton(withTitle: "Cancel")
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        permissionCheckBusy = true
        Task { [weak self] in
            guard let self else { return }
            let report = await permission.diagnostic()
            permissionCheckBusy = false
            message("Screen access diagnostic", report)
        }
    }

    @objc private func previewResults() {
        guard session.phase == .idle, !permissionCheckBusy, !handoffBusy else { return }
        let prompt = NSAlert()
        prompt.messageText = "Preview the result workflow"
        prompt.informativeText = "Try the chooser, destination confirmation and error recovery with synthetic QR results. This preview does not capture your screen or open another application. Open actions intentionally show a simulated failure so you can try recovery. Copy changes the clipboard; Save writes the displayed text only after you choose a destination."
        prompt.addButton(withTitle: "Show synthetic results")
        prompt.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard prompt.runModal() == .alertFirstButtonReturn else { return }
        reportWindow?.close()
        controlsWindow?.orderOut(nil)
        if resultPreview == nil { resultPreview = SyntheticResultPreviewController() }
        resultPreview?.start()
    }

    private func runCapture(_ selection: Selection) {
        let token = selection.sessionID
        guard session.advance(token, from: .selecting, to: .capturing) else { return }
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.session.contains(token) else { return }
            self.fail(.timedOut)
        }
        progressTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, self.session.contains(token) else { return }
            self.statusItem.button?.title = "Reading…"
        }
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let frame = try await self.capture.capture(selection)
                guard self.session.advance(token, from: .capturing, to: .decoding) else { return }
                self.overlay.close()
                let items = try await self.decoder.decode(frame)
                guard self.session.advance(token, from: .decoding, to: .reviewing) else { return }
                self.finish(token)
                self.showReport(frame: frame, items: items, selection: selection)
            } catch is CancellationError { /* Invalidated completions have no side effects. */ }
            catch {
                guard self.session.contains(token) else { return }
                self.fail(error as? ScanFailure ?? .captureFailed)
            }
        }
    }

    @objc private func cancel() {
        guard let token = session.id else { return }
        finish(token)
    }
    private func finish(_ token: UUID) {
        guard session.finish(token) else { return }
        scanTask?.cancel(); scanTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        progressTask?.cancel(); progressTask = nil
        overlay.close()
        statusItem.button?.title = ""
    }
    private func fail(_ failure: ScanFailure) {
        guard let token = session.id else { return }
        finish(token)
        let detail: String
        switch failure {
        case .permissionUnavailable: detail = "Screen access is unavailable. Check Privacy & Security settings; a relaunch may be required."
        case .displayChanged: detail = "The display arrangement changed. Start a new selection."
        case .selectionTooSmall: detail = "Select a larger area (at least 12 × 12 points). Include the QR code’s border."
        case .regionTooLarge: detail = "Select a smaller area. This proof limits a capture to 16 million pixels."
        case .timedOut: detail = "The scan took longer than five seconds. Its result will be discarded. Try a smaller area."
        case .decodeFailed: detail = "The captured image could not be processed. Try again."
        default: detail = "Capture failed. Check screen access and the display arrangement, then try again."
        }
        message("Scan could not finish", detail)
    }

    private func showReport(frame: CapturedFrame, items: [DecodedItem], selection: Selection) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 660),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "QRSnap — Capture proof"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let heading = NSTextField(wrappingLabelWithString: "\(frame.pixelWidth) × \(frame.pixelHeight) pixels · Display \(selection.display.id) · \(items.count) QR observation(s)")
        let image = NSImageView()
        image.image = NSImage(cgImage: frame.image, size: NSSize(width: frame.pixelWidth, height: frame.pixelHeight))
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel("Captured region. Inspect for correct crop and overlay exclusion.")
        image.heightAnchor.constraint(equalToConstant: 320).isActive = true
        let details = items.isEmpty ? "No QR code detected. Try selecting a larger area including its border." : items.map {
            let preview = $0.payload.map { String($0.prefix(512)) } ?? "Unsupported: QR has no text payload."
            return "QR \($0.id + 1): \(preview)"
        }.joined(separator: "\n\n")
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        let markers = G0MarkerEvidence.describe(frame.image).map { "\n\n\($0)" } ?? ""
        text.string = "\(details)\(markers)\n\nFeasibility build: QR destinations are displayed here. Automatic routing will be integrated after the runtime checks pass. Close this window to release the preview."
        text.font = .systemFont(ofSize: 14)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = text
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(image)
        stack.addArrangedSubview(scroll)
        window.contentView = stack
        reportWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === reportWindow else { return }
        window.contentView = nil
        reportWindow = nil
    }

    @objc private func toggleShortcut(_ sender: Any) {
        if shortcutEnabled {
            shortcut.unregister()
            shortcutEnabled = false
        } else {
            let status = shortcut.register()
            shortcutEnabled = status == noErr
            if !shortcutEnabled {
                message("Shortcut unavailable", "Control-Shift-Q could not be registered (status \(status)). Use the Scan menu command. Registration does not detect every possible shortcut conflict.")
            }
        }
        shortcutMenuItem?.state = shortcutEnabled ? .on : .off
        shortcutButton?.state = shortcutEnabled ? .on : .off
    }

    private var textDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "local.benny.QRSnap", isDirectory: true)
            .appendingPathComponent("Scanned Text", isDirectory: true)
    }
    @objc private func testTextHandoff() {
        guard !handoffBusy else { return }
        let alert = NSAlert()
        alert.messageText = "Test the default text application"
        alert.informativeText = "This writes a synthetic UTF-8 text file and opens it with your default .txt application. The file is kept in Application Support until you remove it. No system defaults change."
        alert.addButton(withTitle: "Create and open test file")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let url = try TextDocumentStore(directory: textDirectory).createDocument(text: "QRSnap synthetic handoff\nGrüezi · 日本語 · 🐱\nSecond line\n")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.addsToRecentItems = false
            handoffBusy = true
            NSWorkspace.shared.open(url, configuration: configuration) { [weak self] _, error in
                let succeeded = error == nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handoffBusy = false
                    self.message(succeeded ? "Handoff accepted" : "Handoff failed",
                                 succeeded ? "Verify the text in the receiving editor. The callback alone does not prove it rendered correctly. The test file is retained."
                                           : "The default application could not open the test document. The file is retained; use Show scanned text files to inspect it.")
                }
            }
        } catch { message("Text write failed", "The synthetic document could not be created.") }
    }
    @objc private func showTextFiles() {
        do {
            try FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            NSWorkspace.shared.activateFileViewerSelecting([textDirectory])
        } catch { message("Folder unavailable", "The text folder could not be created.") }
    }
    @objc private func about() {
        message("QRSnap · Feasibility milestone", "Native macOS 14+ QR selection proof. Enable the test shortcut to try Control-Shift-Q while another app is foreground. Screen access is requested only from Scan. Text documents persist until you remove them. No screenshot files, analytics, or network requests are created. Multi-display, Spaces, permission and sandbox handoff checks remain to be run. Drag selection is not fully accessible to nonvisual users.")
    }
    private func message(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        cancel()
        resultPreview?.dismiss()
        shortcut.unregister()
        reportWindow?.close()
    }
}
