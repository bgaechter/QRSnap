import AppKit
// The macOS 15 SDK lacks Sendable annotations for SCShareableContent.
// Application-side use of its read-only snapshot stays in this MainActor adapter;
// no content references are stored or shared with other application tasks.
// Keep this legacy SDK workaround local; see docs/ci.md.
@preconcurrency import ScreenCaptureKit

@MainActor final class ScreenPermissionService: ScreenPermissionChecking {
    var isGranted: Bool { CGPreflightScreenCaptureAccess() }
    func request() -> Bool { CGRequestScreenCaptureAccess() }

    /// Explicit feasibility diagnostic only. Enumerates no content in the report,
    /// captures no pixels, and does not treat a successful query as capture success.
    func diagnostic() async -> String {
        let before = isGranted
        let result: String
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            result = "ScreenCaptureKit shareable-content query: accepted."
        } catch {
            let error = error as NSError
            let category = error.domain == SCStreamErrorDomain ? "SCStreamErrorDomain" : "other domain"
            result = "ScreenCaptureKit shareable-content query: failed (\(category), code \(error.code))."
        }
        return "Screen preflight before: \(before).\n\(result)\nScreen preflight after: \(isGranted).\n\nNo pixels were captured. A successful query does not prove a successful capture."
    }
}

@MainActor enum DisplayInventory {
    static var current: [DisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return DisplayGeometry(id: number.uint32Value, frame: screen.frame, backingScale: screen.backingScaleFactor)
        }.sorted { $0.id < $1.id }
    }
}

/// G0 experimental adapter. Runtime source mapping and exclusion remain gates.
@MainActor final class ScreenCaptureService: ScreenCapturing {
    func capture(_ selection: Selection) async throws -> CapturedFrame {
        guard CGPreflightScreenCaptureAccess() else { throw ScanFailure.permissionUnavailable }
        guard selection.topology == DisplayInventory.current else { throw ScanFailure.displayChanged }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            try Task.checkCancellation()
            guard selection.topology == DisplayInventory.current,
                  let display = content.displays.first(where: { $0.displayID == selection.display.id }) else {
                throw ScanFailure.displayChanged
            }
            // Never silently proceed without identifying our own app for exclusion.
            guard let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
                throw ScanFailure.captureFailed
            }
            let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
            let region = try GeometryAdapter.pixelRegion(rect: selection.rectInDisplayTopLeftPoints,
                                                        displaySize: selection.display.size,
                                                        scale: CGFloat(filter.pointPixelScale))
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = region.sourceRectInPoints
            configuration.width = region.width
            configuration.height = region.height
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.scalesToFit = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            guard selection.topology == DisplayInventory.current else { throw ScanFailure.displayChanged }
            guard image.width == region.width, image.height == region.height else { throw ScanFailure.captureFailed }
            return CapturedFrame(image: image, orientation: .up)
        } catch let failure as ScanFailure { throw failure }
        catch is CancellationError { throw CancellationError() }
        catch {
            throw CGPreflightScreenCaptureAccess() ? ScanFailure.captureFailed : ScanFailure.permissionUnavailable
        }
    }
}
