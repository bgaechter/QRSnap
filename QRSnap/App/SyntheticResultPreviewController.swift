import AppKit

/// Explicit feasibility preview of the real workflow and result windows. None of
/// these capture/decode/storage/launch boundaries access the screen or another app.
/// Copy/Save remain real, deliberate actions in ScanResultWindowController.
@MainActor final class SyntheticResultPreviewController {
    private var presentedSession: UUID?
    private lazy var results = ScanResultWindowController(title: "QRSnap — Synthetic result preview") { [weak self] action in
        self?.act(action)
    }
    private lazy var workflow = ScanWorkflow(capture: PreviewCapture(), decoder: PreviewDecoder(),
                                            textStore: PreviewStore(), makeLauncher: { isCurrent in
        PreviewLauncher(isCurrent: isCurrent)
    }) { [weak self] event in
        guard let self else { return }
        switch event {
        case .choose(let token, _), .finished(let token, .failed): presentedSession = token
        case .actionRequired(let request): presentedSession = request.sessionID
        case .finished(let token, _):
            if presentedSession == token { presentedSession = nil }
        default: break
        }
        results.receive(event)
    }

    func start() {
        dismiss()
        guard let token = workflow.beginSelection() else { return }
        let display = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), backingScale: 1)
        workflow.submit(Selection(sessionID: token, display: display, topology: [display],
                                  rect: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }

    func dismiss() {
        presentedSession = nil
        if let token = workflow.sessionID { workflow.cancel(sessionID: token) }
        results.dismiss()
    }

    private func act(_ action: ScanResultWindowController.Action) {
        switch action {
        case .choose(let token, let observation): workflow.choose(sessionID: token, observationID: observation)
        case .confirm(let request): workflow.confirm(requestID: request)
        case .openAsText(let request): workflow.openAsText(requestID: request)
        case .cancel(let token):
            if workflow.sessionID == token { workflow.cancel(sessionID: token) }
            if presentedSession == token { presentedSession = nil }
        case .retry(let token):
            guard presentedSession == token, workflow.sessionID == nil else { return }
            start()
        }
    }
}

@MainActor private final class PreviewCapture: ScreenCapturing {
    func capture(_ selection: Selection) async throws -> CapturedFrame {
        let data = Data([255, 255, 255, 255]) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw ScanFailure.captureFailed }
        return CapturedFrame(image: image)
    }
}

private struct PreviewDecoder: QRDecoding {
    func decode(_ frame: CapturedFrame) async throws -> [DecodedItem] {
        let payloads: [String?] = [
            "qrsnap-preview://example/action",
            "file:///synthetic/blocked.txt",
            "  QRSnap synthetic text\nGrüezi · 日本語 · 🐱\nSecond line\t",
            nil,
            "",
            "qrsnap-preview://example/action",
            "https://example.com/qr-preview"
        ]
        return payloads.enumerated().map { DecodedItem(id: $0.offset, payload: $0.element, bounds: .zero) }
    }
}

private struct PreviewStore: TextDocumentStoring {
    func createDocument(text: String) throws -> URL {
        // Exercise recoverable text errors without creating an automatic document.
        throw ScanFailure.fileWriteFailed
    }
}

@MainActor private final class PreviewLauncher: PayloadLaunching {
    private let isCurrent: @MainActor () -> Bool
    init(isCurrent: @escaping @MainActor () -> Bool) { self.isCurrent = isCurrent }
    func handler(for url: URL) -> HandlerMetadata? {
        guard isCurrent() else { return nil }
        return HandlerMetadata(name: "Synthetic example app", applicationURL: URL(fileURLWithPath: "/synthetic/Example.app"))
    }
    func open(_ url: URL) async -> LaunchResult {
        // Intentionally show recovery UI; never call NSWorkspace or another app.
        .failure(.launchFailed)
    }
}
