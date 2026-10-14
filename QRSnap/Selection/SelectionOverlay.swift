import AppKit

@MainActor final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class SelectionView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var onStart: (() -> Bool)?
    var onFinish: ((CGPoint, CGPoint) -> Void)?
    var onCancel: (() -> Void)?
    private var start: CGPoint?
    private var end: CGPoint?
    private var submitted = false

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        guard !submitted, onStart?() == true else { return }
        window?.makeKey()
        window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil)
        end = start
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard start != nil, !submitted else { return }
        end = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start, !submitted else { return }
        submitted = true
        onFinish?(start, convert(event.locationInWindow, from: nil))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.24).setFill()
        bounds.fill()
        if let start, let end {
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(start.x - end.x), height: abs(start.y - end.y)).intersection(bounds)
            NSColor.white.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 2
            outline.stroke()
        }
        let instruction = "Select the whole QR code, including its border. Escape cancels."
        instruction.draw(at: CGPoint(x: 28, y: 40), withAttributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.white
        ])
    }
}

@MainActor final class SelectionOverlay {
    private var panels: [SelectionPanel] = []
    private var activeDisplay: UInt32?
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var completion: ((Result<Selection?, ScanFailure>) -> Void)?
    private var cursorPushed = false

    func show(sessionID: UUID, completion: @escaping (Result<Selection?, ScanFailure>) -> Void) {
        close()
        self.completion = completion
        let topology = DisplayInventory.current
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = topology.first(where: { $0.id == number.uint32Value }) else { continue }
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.setAccessibilityLabel("QR selection. Drag within one display. Press Escape to cancel.")
            view.onStart = { [weak self] in
                guard let self, self.activeDisplay == nil else { return false }
                self.activeDisplay = display.id
                return true
            }
            view.onFinish = { [weak self] start, end in
                guard let self, self.activeDisplay == display.id else { return }
                do {
                    let rect = try GeometryAdapter.selection(start: start, end: end, displaySize: display.size)
                    let selected = rect.map { Selection(sessionID: sessionID, display: display, topology: topology, rect: $0) }
                    // Keep panels visible for the exclusion experiment until capture completes.
                    let callback = self.completion
                    self.completion = nil
                    callback?(.success(selected))
                } catch { self.resolve(.failure(error as? ScanFailure ?? .invalidSelection)) }
            }
            view.onCancel = { [weak self] in self?.resolve(.success(nil)) }
            panel.contentView = view
            panel.makeFirstResponder(view)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        guard !panels.isEmpty else { resolve(.failure(.displayChanged)); return }
        let mouse = NSEvent.mouseLocation
        (panels.first { $0.frame.contains(mouse) } ?? panels[0]).makeKey()
        NSCursor.crosshair.push()
        cursorPushed = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                MainActor.assumeIsolated { self?.cancelRequested?() }
                return nil
            }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayChanged?() }
        }
    }

    var cancelRequested: (() -> Void)?
    var displayChanged: (() -> Void)?

    private func resolve(_ result: Result<Selection?, ScanFailure>) {
        let callback = completion
        close()
        callback?(result)
    }

    func close() {
        completion = nil
        panels.forEach { $0.close() }
        panels.removeAll()
        activeDisplay = nil
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
