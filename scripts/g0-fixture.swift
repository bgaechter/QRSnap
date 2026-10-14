import AppKit

/// Separate synthetic source application; it never captures or requests permission.
@MainActor final class FixtureView: NSView {
    var phaseB = false { didSet { needsDisplay = true } }
    let qr = NSImage(contentsOf: Bundle.main.url(forResource: "https", withExtension: "png")!)!
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSGraphicsContext.current?.shouldAntialias = false
        qr.draw(in: CGRect(x: 60, y: 60, width: 280, height: 280),
                from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        let colors: [NSColor] = [phaseB ? .magenta : .red, .green, .blue, .yellow]
        let points = [CGPoint(x: 10, y: 10), CGPoint(x: 382, y: 10),
                      CGPoint(x: 10, y: 382), CGPoint(x: 382, y: 382)]
        for (color, point) in zip(colors, points) {
            color.setFill()
            CGRect(origin: point, size: CGSize(width: 8, height: 8)).fill()
        }
    }
}

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let view = FixtureView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let root = NSMenuItem()
        let submenu = NSMenu(title: "G0 Fixture")
        let change = NSMenuItem(title: "Change marker phase", action: #selector(changePhase), keyEquivalent: "m")
        change.target = self
        submenu.addItem(change)
        submenu.addItem(NSMenuItem(title: "Quit G0 Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        root.submenu = submenu
        menu.addItem(root)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 400, height: 400),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "G0 Synthetic Fixture — phase A"
        // Keep the synthetic source unobstructed when the reader activates its
        // controls. This affects only the test source, not the capture adapter.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        updateTitle()
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func changePhase() {
        view.phaseB.toggle()
        updateTitle()
    }
    func windowDidMove(_ notification: Notification) { updateTitle() }
    func windowDidResize(_ notification: Notification) { updateTitle() }
    private func updateTitle() {
        guard let window, let screen = window.screen else { return }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        window.title = "G0 phase \(view.phaseB ? "B" : "A") · select x=\(Int(rect.minX - screen.frame.minX)) y=\(Int(screen.frame.maxY - rect.maxY)) w=\(Int(rect.width)) h=\(Int(rect.height)) points"
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct FixtureMain {
    @MainActor static func main() {
        // The helper script bundles only the committed synthetic QR fixture.
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
