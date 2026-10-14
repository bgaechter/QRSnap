import Foundation
import CoreGraphics
import ImageIO

public struct DisplayGeometry: Equatable, Sendable {
    public let id: UInt32
    public let frameInGlobalBottomLeftPoints: CGRect
    public let backingScale: CGFloat

    public init(id: UInt32, frame: CGRect, backingScale: CGFloat) {
        self.id = id
        self.frameInGlobalBottomLeftPoints = frame
        self.backingScale = backingScale
    }

    public var size: CGSize { frameInGlobalBottomLeftPoints.size }
}

public struct Selection: Sendable {
    public let sessionID: UUID
    public let display: DisplayGeometry
    public let topology: [DisplayGeometry]
    /// Display-local logical points, origin at top left. Never global pixels.
    public let rectInDisplayTopLeftPoints: CGRect

    public init(sessionID: UUID, display: DisplayGeometry, topology: [DisplayGeometry], rect: CGRect) {
        self.sessionID = sessionID
        self.display = display
        self.topology = topology
        self.rectInDisplayTopLeftPoints = rect
    }
}

public struct CapturedFrame: Sendable {
    public let image: CGImage
    public let orientation: CGImagePropertyOrientation
    public var pixelWidth: Int { image.width }
    public var pixelHeight: Int { image.height }

    public init(image: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.image = image
        self.orientation = orientation
    }
}

public struct DecodedItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public let payload: String?
    /// Vision coordinates: normalized, origin at bottom left.
    public let boundsInImageBottomLeft: CGRect

    public init(id: Int, payload: String?, bounds: CGRect) {
        self.id = id
        self.payload = payload
        self.boundsInImageBottomLeft = bounds
    }
}

public enum ScanFailure: String, Error, Sendable {
    case permissionUnavailable, displayChanged, invalidSelection, selectionTooSmall
    case captureFailed, timedOut, noQR, unsupportedPayload, handlerUnavailable
    case fileWriteFailed, launchFailed, regionTooLarge, decodeFailed
}

public struct HandlerMetadata: Equatable, Sendable {
    public let name: String
    public let applicationURL: URL
}

public enum Route: Equatable, Sendable {
    case webURL(URL)
    case confirmedExternalURI(URL, HandlerMetadata)
    case plainText(String)
    case blockedText(String)
    case unsupported(ScanFailure)
}

public enum LaunchResult: Equatable, Sendable {
    case handoffSucceeded
    case failure(ScanFailure)
}

@MainActor public protocol ScreenCapturing {
    func capture(_ selection: Selection) async throws -> CapturedFrame
}
public protocol QRDecoding: Sendable {
    func decode(_ frame: CapturedFrame) async throws -> [DecodedItem]
}
@MainActor public protocol ScreenPermissionChecking {
    var isGranted: Bool { get }
    func request() -> Bool
}
@MainActor public protocol PayloadLaunching {
    func handler(for url: URL) -> HandlerMetadata?
    func open(_ url: URL) async -> LaunchResult
}
public protocol TextDocumentStoring: Sendable {
    func createDocument(text: String) throws -> URL
}
