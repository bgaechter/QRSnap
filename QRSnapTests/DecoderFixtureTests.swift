#if !STANDALONE_TESTS
import XCTest
#endif
import ImageIO
import CoreImage
import Vision
#if STANDALONE_TESTS
import Foundation
#elseif SWIFT_PACKAGE
@testable import QRSnapCore
#else
@testable import QRSnap
#endif

@MainActor final class DecoderFixtureTests: XCTestCase {
    struct Fixture: Decodable {
        let file: String
        let kind: String
        let payloads: [String?]
        let sourcePayloadsHex: [String]?
    }
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
        for fixture in fixtures where fixture.kind == "baseline" || fixture.kind == "negative" {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent(fixture.file) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let results = try await decoder.decode(CapturedFrame(image: image))
            XCTAssertEqual(results.map(\.payload), fixture.payloads, fixture.file)
        }
    }
    func testEmptyAndUnsupportedObservationsRemainDistinct() async throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
            .filter { $0.kind == "payload-edge" }
        XCTAssertEqual(Set(fixtures.map(\.file)), Set(["empty.png", "binary.png", "mixed-text-binary.png"]))
        let decoder = QRDecoder()
        for fixture in fixtures {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent(fixture.file) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let results = try await decoder.decode(CapturedFrame(image: image))
            // This checks observation count and top-to-bottom order, including nil.
            XCTAssertEqual(results.map(\.payload), fixture.payloads, fixture.file)
            XCTAssertEqual(Set(results.map(\.id)).count, results.count, fixture.file)
            for item in results {
                if item.payload == nil {
                    XCTAssertEqual(PayloadClassifier.classify(item.payload), .unsupported, fixture.file)
                } else if item.payload == "" {
                    XCTAssertEqual(PayloadClassifier.classify(item.payload), .plainText(""), fixture.file)
                }
            }

            // Independent fixture-integrity check: binary input is not assumed to
            // imply nil text. Verify Vision sees the encoded bytes as well.
            let request = VNDetectBarcodesRequest()
            request.revision = VNDetectBarcodesRequestRevision4
            request.symbologies = [.qr]
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
            let actualBytes = try (request.results ?? []).map { observation in
                let descriptor = try XCTUnwrap(observation.barcodeDescriptor as? CIQRCodeDescriptor)
                return try byteModeFixturePayload(descriptor).map { String(format: "%02x", $0) }.joined()
            }
            // Vision's enumeration order is unspecified; production ordering is
            // asserted above, and this check compares only the byte multiset.
            let expectedBytes = try XCTUnwrap(fixture.sourcePayloadsHex)
            XCTAssertEqual(actualBytes.sorted(), expectedBytes.sorted(), fixture.file)
        }
    }
    private enum FixtureError: Error { case unexpectedEncoding }
    private func byteModeFixturePayload(_ descriptor: CIQRCodeDescriptor) throws -> Data {
        // Only our short, single-segment byte-mode fixtures, versions 1...9.
        // Descriptor data is QR codewords (mode/count/data/padding), not the
        // message itself. Never use this fixture validator in app routing.
        let words = [UInt8](descriptor.errorCorrectedPayload)
        guard (1...9).contains(descriptor.symbolVersion), words.count >= 2,
              words[0] >> 4 == 4 else { throw FixtureError.unexpectedEncoding }
        let count = (Int(words[0] & 0x0f) << 4) | Int(words[1] >> 4)
        guard count <= words.count - 2,
              words[count + 1] & 0x0f == 0 else { throw FixtureError.unexpectedEncoding }
        return Data((0..<count).map { index in
            (words[index + 1] & 0x0f) << 4 | words[index + 2] >> 4
        })
    }
    func testCharacterizationRecordsObservedCounts() async throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        let decoder = QRDecoder()
        for fixture in fixtures where fixture.kind == "characterization" {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent(fixture.file) as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let results = try await decoder.decode(CapturedFrame(image: image))
            // Fixture names and counts are synthetic; never log captured payloads.
            print("CHARACTERIZATION \(fixture.file): observations=\(results.count), exact=\(results.map(\.payload) == fixture.payloads)")
        }
    }
}
