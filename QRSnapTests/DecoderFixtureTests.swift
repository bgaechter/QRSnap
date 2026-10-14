#if !STANDALONE_TESTS
import XCTest
#endif
import ImageIO
#if STANDALONE_TESTS
import Foundation
#elseif SWIFT_PACKAGE
@testable import QRSnapCore
#else
@testable import QRSnap
#endif

@MainActor final class DecoderFixtureTests: XCTestCase {
    struct Fixture: Decodable { let file: String; let kind: String; let payloads: [String] }
    private var directory: URL {
        #if STANDALONE_TESTS
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        #elseif SWIFT_PACKAGE
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
        #else
        Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil)!
        #endif
    }
    func testSupportedBaselineAndNegativeImages() async throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        let decoder = QRDecoder()
        for fixture in fixtures where fixture.kind != "characterization" {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent(fixture.file) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let results = try await decoder.decode(CapturedFrame(image: image))
            XCTAssertEqual(results.map(\.payload), fixture.payloads.map(Optional.some), fixture.file)
        }
    }
    func testCharacterizationRecordsObservedCounts() async throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        let decoder = QRDecoder()
        for fixture in fixtures where fixture.kind == "characterization" {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent(fixture.file) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let results = try await decoder.decode(CapturedFrame(image: image))
            // Fixture names and counts are synthetic; never log captured payloads.
            print("CHARACTERIZATION \(fixture.file): observations=\(results.count), exact=\(results.map(\.payload) == fixture.payloads.map(Optional.some))")
        }
    }
}
