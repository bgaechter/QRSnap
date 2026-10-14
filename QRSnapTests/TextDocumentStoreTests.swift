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

@MainActor final class TextDocumentStoreTests: XCTestCase {
    func testUniquePrivateDocumentsPreserveExactUTF8AndRemainOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TextDocumentStore(directory: root)
        let value = "\u{FEFF}Grüezi 日本語 🐱\r\n  trailing\n"
        let first = try store.createDocument(text: value)
        let second = try store.createDocument(text: value)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.pathExtension, "txt")
        XCTAssertNotNil(UUID(uuidString: first.deletingPathExtension().lastPathComponent))
        for url in [first, second] {
            XCTAssertEqual(try Data(contentsOf: url), Data(value.utf8))
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 2)
        let permissions = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o700)
    }
    func testWriteFailureIsTypedAndDoesNotOverwriteExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("existing".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try TextDocumentStore(directory: root).createDocument(text: "replacement")) {
            XCTAssertEqual($0 as? ScanFailure, .fileWriteFailed)
        }
        XCTAssertEqual(try String(contentsOf: root, encoding: .utf8), "existing")
    }
}
