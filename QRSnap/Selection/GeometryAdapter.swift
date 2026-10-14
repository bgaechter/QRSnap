import Foundation

public enum GeometryAdapter {
    /// Both endpoints are in the flipped overlay view's local point coordinates.
    public static func selection(start: CGPoint, end: CGPoint, displaySize: CGSize) throws -> CGRect? {
        guard [start.x, start.y, end.x, end.y, displaySize.width, displaySize.height].allSatisfy(\.isFinite),
              displaySize.width > 0, displaySize.height > 0 else { throw ScanFailure.invalidSelection }
        let clamp: (CGPoint) -> CGPoint = { point in
            CGPoint(x: min(max(point.x, 0), displaySize.width),
                    y: min(max(point.y, 0), displaySize.height))
        }
        let a = clamp(start), b = clamp(end)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(a.x - b.x), height: abs(a.y - b.y))
        guard rect.width > 0, rect.height > 0 else { return nil }
        guard rect.width >= 12, rect.height >= 12 else { throw ScanFailure.selectionTooSmall }
        return rect
    }

    public struct PixelRegion: Equatable, Sendable {
        public let sourceRectInPoints: CGRect
        public let width: Int
        public let height: Int
    }

    /// Proposed G0 convention: expand edges to pixel boundaries, then capture 1:1.
    /// Arithmetic is unit tested; AppKit → ScreenCaptureKit mapping needs marker tests.
    public static func pixelRegion(rect: CGRect, displaySize: CGSize, scale: CGFloat,
                                   maximumPixels: Int = 16_000_000) throws -> PixelRegion {
        guard [rect.minX, rect.minY, rect.width, rect.height, displaySize.width,
               displaySize.height, scale].allSatisfy(\.isFinite),
              scale > 0, rect.width > 0, rect.height > 0,
              rect.minX >= 0, rect.minY >= 0,
              rect.maxX <= displaySize.width, rect.maxY <= displaySize.height,
              maximumPixels > 0 else { throw ScanFailure.invalidSelection }
        let x0 = floor(rect.minX * scale), y0 = floor(rect.minY * scale)
        let x1 = min(ceil(rect.maxX * scale), floor(displaySize.width * scale))
        let y1 = min(ceil(rect.maxY * scale), floor(displaySize.height * scale))
        let w = x1 - x0, h = y1 - y0
        guard w.isFinite, h.isFinite, w >= 1, h >= 1,
              w <= CGFloat(maximumPixels), h <= CGFloat(maximumPixels),
              w * h <= CGFloat(maximumPixels) else { throw ScanFailure.regionTooLarge }
        return PixelRegion(sourceRectInPoints: CGRect(x: x0 / scale, y: y0 / scale,
                                                       width: w / scale, height: h / scale),
                           width: Int(w), height: Int(h))
    }

    public static func readingOrder(_ items: [DecodedItem]) -> [DecodedItem] {
        items.sorted {
            let a = $0.boundsInImageBottomLeft, b = $1.boundsInImageBottomLeft
            if a.maxY != b.maxY { return a.maxY > b.maxY }
            if a.minX != b.minX { return a.minX < b.minX }
            return $0.id < $1.id
        }
    }
}
