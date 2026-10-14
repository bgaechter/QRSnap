import CoreGraphics
import Foundation

/// In-memory measurement for the explicit 800×800 synthetic G0 fixture only.
/// No pixels or decoded payloads are written or logged.
enum G0MarkerEvidence {
    static func describe(_ image: CGImage) -> String? {
        guard image.width == 800, image.height == 800 else { return nil }
        var pixels = [UInt8](repeating: 0, count: 800 * 800 * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 800, height: 800,
                                          bitsPerComponent: 8, bytesPerRow: 3200,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                            CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 800, height: 800))
            return true
        }
        guard rendered else { return nil }
        var bounds = Array(repeating: [800, 800, -1, -1, 0], count: 5)
        for y in 0..<800 {
            for x in 0..<800 {
                let offset = (y * 800 + x) * 4
                let r = pixels[offset], g = pixels[offset + 1], b = pixels[offset + 2]
                let marker: Int?
                if r > 200 && g < 60 && b < 60 { marker = 0 }
                else if r < 60 && g > 200 && b < 60 { marker = 1 }
                else if r < 60 && g < 60 && b > 200 { marker = 2 }
                else if r > 200 && g > 200 && b < 60 { marker = 3 }
                else if r > 200 && g < 60 && b > 200 { marker = 4 }
                else { marker = nil }
                guard let marker else { continue }
                bounds[marker][0] = min(bounds[marker][0], x)
                bounds[marker][1] = min(bounds[marker][1], y)
                bounds[marker][2] = max(bounds[marker][2], x)
                bounds[marker][3] = max(bounds[marker][3], y)
                bounds[marker][4] += 1
            }
        }
        let first = bounds[4][4] > bounds[0][4] ? 4 : 0
        let indices = [first, 1, 2, 3]
        guard indices.allSatisfy({ bounds[$0][4] >= 196 }) else { return nil }
        let expected = [[20, 20, 35, 35], [764, 20, 779, 35],
                        [20, 764, 35, 779], [764, 764, 779, 779]]
        let error = zip(indices, expected).flatMap { index, target in
            zip(bounds[index].prefix(4), target).map { abs($0 - $1) }
        }.max()!
        let coordinates = indices.map { bounds[$0].prefix(4).map(String.init).joined(separator: ",") }.joined(separator: "; ")
        return "G0 synthetic markers: phase \(first == 4 ? "B" : "A"), maximum edge error \(error) px (target ≤ 1). Bounds: \(coordinates)."
    }
}
