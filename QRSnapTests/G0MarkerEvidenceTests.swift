#if !STANDALONE_TESTS
import XCTest
#endif
import CoreGraphics
import Foundation
#if SWIFT_PACKAGE
@testable import QRSnapCore
#elseif !STANDALONE_TESTS
@testable import QRSnap
#endif

@MainActor final class G0MarkerEvidenceTests: XCTestCase {
    private func fixture(offset: Int = 0, phaseB: Bool = false, markers: Bool = true) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: 800 * 800 * 4)
        let colors: [[UInt8]] = [[255, 0, phaseB ? 255 : 0, 255], [0, 255, 0, 255],
                                  [0, 0, 255, 255], [255, 255, 0, 255]]
        if markers {
            for (point, color) in zip([(20, 20), (764, 20), (20, 764), (764, 764)], colors) {
                for y in point.1..<(point.1 + 16) {
                    for x in (point.0 + offset)..<(point.0 + 16 + offset) {
                        let index = (y * 800 + x) * 4
                        pixels.replaceSubrange(index..<(index + 4), with: color)
                    }
                }
            }
        }
        return CGImage(width: 800, height: 800, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 3200,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    func testKnownMarkerEdgesAndFramePhase() {
        XCTAssertTrue(G0MarkerEvidence.describe(fixture())!.contains("phase A, maximum edge error 0 px"))
        XCTAssertTrue(G0MarkerEvidence.describe(fixture(phaseB: true))!.contains("phase B, maximum edge error 0 px"))
        XCTAssertTrue(G0MarkerEvidence.describe(fixture(offset: 1))!.contains("maximum edge error 1 px"))
        XCTAssertTrue(G0MarkerEvidence.describe(fixture(offset: 2))!.contains("maximum edge error 2 px"))
    }
    func testNonFixtureDoesNotClaimMarkerEvidence() {
        XCTAssertNil(G0MarkerEvidence.describe(fixture(markers: false)))
        let cropped = fixture().cropping(to: CGRect(x: 0, y: 0, width: 799, height: 800))!
        XCTAssertNil(G0MarkerEvidence.describe(cropped))
    }
}
