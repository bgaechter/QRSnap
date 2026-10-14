#if !STANDALONE_TESTS
import XCTest
#endif
#if STANDALONE_TESTS
import Foundation
#elseif SWIFT_PACKAGE
@testable import QRSnapCore
#else
@testable import QRSnap
#endif

@MainActor final class GeometryTests: XCTestCase {
    func testAllDragDirectionsUseTheSameLocalRectangle() throws {
        for (a, b) in [(CGPoint(x: 20, y: 30), CGPoint(x: 100, y: 130)),
                       (CGPoint(x: 100, y: 130), CGPoint(x: 20, y: 30)),
                       (CGPoint(x: 20, y: 130), CGPoint(x: 100, y: 30)),
                       (CGPoint(x: 100, y: 30), CGPoint(x: 20, y: 130))] {
            XCTAssertEqual(try GeometryAdapter.selection(start: a, end: b, displaySize: CGSize(width: 200, height: 300)),
                           CGRect(x: 20, y: 30, width: 80, height: 100))
        }
    }
    func testShiftedPortraitDisplayClipsLocally() throws {
        let display = DisplayGeometry(id: 17, frame: CGRect(x: -1080, y: 900, width: 1080, height: 1920), backingScale: 2)
        let rect = try XCTUnwrap(GeometryAdapter.selection(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 1300, y: 2000), displaySize: display.size))
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 980, height: 1820))
        let output = try GeometryAdapter.pixelRegion(rect: rect, displaySize: display.size, scale: 2)
        XCTAssertEqual(output.width, 1960)
        XCTAssertEqual(output.height, 3640)
    }
    func testClickCancelsAndSmallSelectionIsTypedFailure() throws {
        XCTAssertNil(try GeometryAdapter.selection(start: .zero, end: .zero, displaySize: CGSize(width: 100, height: 100)))
        XCTAssertThrowsError(try GeometryAdapter.selection(start: .zero, end: CGPoint(x: 11, y: 60), displaySize: CGSize(width: 100, height: 100))) {
            XCTAssertEqual($0 as? ScanFailure, .selectionTooSmall)
        }
    }
    func testOutwardPixelRoundingAtDifferentScales() throws {
        for scale: CGFloat in [1, 2] {
            let result = try GeometryAdapter.pixelRegion(rect: CGRect(x: 10.25, y: 20.25, width: 12, height: 13), displaySize: CGSize(width: 100, height: 100), scale: scale)
            XCTAssertEqual(result.sourceRectInPoints.minX * scale, floor(10.25 * scale))
            XCTAssertEqual(result.sourceRectInPoints.maxX * scale, ceil(22.25 * scale))
            XCTAssertEqual(result.width, Int(ceil(22.25 * scale) - floor(10.25 * scale)))
        }
    }
    func testInvalidInputsAndMemoryLimit() {
        for rect in [CGRect(x: -1, y: 0, width: 20, height: 20), CGRect(x: 0, y: 0, width: 2000, height: 20), CGRect(x: 0, y: 0, width: 0, height: 20)] {
            XCTAssertThrowsError(try GeometryAdapter.pixelRegion(rect: rect, displaySize: CGSize(width: 1000, height: 1000), scale: 1))
        }
        XCTAssertThrowsError(try GeometryAdapter.pixelRegion(rect: CGRect(x: 0, y: 0, width: 4000, height: 4001), displaySize: CGSize(width: 5000, height: 5000), scale: 1)) {
            XCTAssertEqual($0 as? ScanFailure, .regionTooLarge)
        }
        XCTAssertThrowsError(try GeometryAdapter.pixelRegion(rect: CGRect(x: 0, y: 0, width: 20, height: 20), displaySize: CGSize(width: 100, height: 100), scale: .infinity))
    }
    func testReadingOrderUsesTopLeftAndRetainsPhysicalDuplicates() {
        let bottom = DecodedItem(id: 0, payload: "same", bounds: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        let right = DecodedItem(id: 1, payload: nil, bounds: CGRect(x: 0.6, y: 0.7, width: 0.2, height: 0.2))
        let left = DecodedItem(id: 2, payload: "same", bounds: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.2))
        XCTAssertEqual(GeometryAdapter.readingOrder([bottom, right, left]).map(\.id), [2, 1, 0])
    }
}
